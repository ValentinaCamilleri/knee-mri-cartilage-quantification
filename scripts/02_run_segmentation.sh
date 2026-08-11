#!/usr/bin/env bash
set -euo pipefail

WORK_ROOT="${WORK_ROOT:-/work}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/output}"
NNUNET_RESULTS="${nnUNet_results:-/models}"
NNUNET_DATASET="${NNUNET_DATASET:-501}"
NNUNET_DATASET_NAME="${NNUNET_DATASET_NAME:-Dataset501_KneeCartilage}"
NNUNET_TRAINER="${NNUNET_TRAINER:-nnUNetTrainer}"
NNUNET_PLANS="${NNUNET_PLANS:-nnUNetPlans}"
NNUNET_CONFIGURATION="${NNUNET_CONFIGURATION:-3d_fullres}"
NNUNET_CHECKPOINT="${NNUNET_CHECKPOINT:-checkpoint_final.pth}"
NNUNET_FOLDS="${NNUNET_FOLDS:-0}"
NNUNET_DEVICE="${NNUNET_DEVICE:-cuda}"
NNUNET_NPP="${NNUNET_NPP:-3}"
NNUNET_NPS="${NNUNET_NPS:-3}"

PYTHON_BIN="${PYTHON_BIN:-/opt/conda/envs/nnunet/bin/python}"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 sub-XXX"
    exit 1
fi

SUBJECT="$1"

PD_IMAGE="${WORK_ROOT}/${SUBJECT}/input/pd.nii.gz"

SEGMENTATION_WORK="${WORK_ROOT}/${SUBJECT}/segmentation"
NNUNET_INPUT="${SEGMENTATION_WORK}/input"
NNUNET_OUTPUT="${SEGMENTATION_WORK}/prediction"

FINAL_OUTPUT="${OUTPUT_ROOT}/${SUBJECT}/segmentation"

MODEL_DIR="${NNUNET_RESULTS}/${NNUNET_DATASET_NAME}/${NNUNET_TRAINER}__${NNUNET_PLANS}__${NNUNET_CONFIGURATION}"

if [[ ! -e "$PD_IMAGE" ]]; then
    echo "ERROR: Prepared PD image not found:"
    echo "$PD_IMAGE"
    echo "Run 01_prepare_inputs.sh first."
    exit 1
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "ERROR: nnU-Net Python not found:"
    echo "$PYTHON_BIN"
    exit 1
fi

for metadata_file in dataset.json plans.json; do
    if [[ ! -f "${MODEL_DIR}/${metadata_file}" ]]; then
        echo "ERROR: nnU-Net model metadata not found:"
        echo "${MODEL_DIR}/${metadata_file}"
        echo "Mount the nnUNet_results directory at /models or set nnUNet_results."
        exit 1
    fi
done

if [[ "$NNUNET_FOLDS" == "auto" ]]; then
    mapfile -t FOLDS < <(
        find "$MODEL_DIR" -mindepth 2 -maxdepth 2 -type f -path "*/fold_*/${NNUNET_CHECKPOINT}" \
            -printf '%h\n' \
            | sed 's#.*/fold_##' \
            | sort -n
    )
else
    read -r -a FOLDS <<< "${NNUNET_FOLDS//,/ }"
fi

if [[ "${#FOLDS[@]}" -eq 0 ]]; then
    echo "ERROR: No trained folds were selected or discovered in:"
    echo "$MODEL_DIR"
    exit 1
fi

for fold in "${FOLDS[@]}"; do
    checkpoint="${MODEL_DIR}/fold_${fold}/${NNUNET_CHECKPOINT}"
    if [[ ! -f "$checkpoint" ]]; then
        echo "ERROR: Trained checkpoint not found:"
        echo "$checkpoint"
        exit 1
    fi
done

mkdir -p \
    "$NNUNET_INPUT" \
    "$NNUNET_OUTPUT" \
    "$FINAL_OUTPUT"

rm -f "${NNUNET_INPUT:?}"/* "${NNUNET_OUTPUT:?}"/*

# nnU-Net requires channel 0 to end in _0000.nii.gz.
cp -L \
    "$PD_IMAGE" \
    "${NNUNET_INPUT}/${SUBJECT}_0000.nii.gz"

echo "========================================"
echo "Running knee cartilage segmentation"
echo "========================================"
echo "Subject:       $SUBJECT"
echo "Input:         ${NNUNET_INPUT}/${SUBJECT}_0000.nii.gz"
echo "Model:         $MODEL_DIR"
echo "Dataset:       $NNUNET_DATASET"
echo "Configuration: $NNUNET_CONFIGURATION"
echo "Fold(s):       ${FOLDS[*]}"
echo "Device:        $NNUNET_DEVICE"
echo

"$PYTHON_BIN" -c \
    'from nnunetv2.inference.predict_from_raw_data import predict_entry_point; predict_entry_point()' \
    -i "$NNUNET_INPUT" \
    -o "$NNUNET_OUTPUT" \
    -d "$NNUNET_DATASET" \
    -tr "$NNUNET_TRAINER" \
    -p "$NNUNET_PLANS" \
    -c "$NNUNET_CONFIGURATION" \
    -f "${FOLDS[@]}" \
    -chk "$NNUNET_CHECKPOINT" \
    -device "$NNUNET_DEVICE" \
    -npp "$NNUNET_NPP" \
    -nps "$NNUNET_NPS"

PREDICTION="${NNUNET_OUTPUT}/${SUBJECT}.nii.gz"
FINAL_SEGMENTATION="${FINAL_OUTPUT}/${SUBJECT}_cartilage.nii.gz"

if [[ ! -f "$PREDICTION" ]]; then
    echo "ERROR: Expected prediction was not generated:"
    echo "$PREDICTION"
    exit 1
fi

cp "$PREDICTION" "$FINAL_SEGMENTATION"

echo
echo "Segmentation completed successfully."
echo "Output:"
echo "$FINAL_SEGMENTATION"
