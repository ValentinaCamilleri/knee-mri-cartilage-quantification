#!/usr/bin/env bash
set -euo pipefail

NNUNET_RESULTS="${nnUNet_results:-/models}"
NNUNET_DATASET_NAME="${NNUNET_DATASET_NAME:-Dataset501_KneeCartilage}"
NNUNET_TRAINER="${NNUNET_TRAINER:-nnUNetTrainer}"
NNUNET_PLANS="${NNUNET_PLANS:-nnUNetPlans}"
NNUNET_CONFIGURATION="${NNUNET_CONFIGURATION:-3d_fullres}"
NNUNET_CHECKPOINT="${NNUNET_CHECKPOINT:-checkpoint_final.pth}"
NNUNET_FOLDS="${NNUNET_FOLDS:-0}"
PYTHON_BIN="${PYTHON_BIN:-/opt/conda/envs/nnunet/bin/python}"

MODEL_DIR="${NNUNET_RESULTS}/${NNUNET_DATASET_NAME}/${NNUNET_TRAINER}__${NNUNET_PLANS}__${NNUNET_CONFIGURATION}"

for command_name in \
    mrinfo mrconvert mrgrid mrregister mrtransform \
    dwidenoise mrdegibbs dwifslpreproc dwibiascorrect \
    dwi2tensor tensor2metric
do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: Required command is missing: $command_name"
        exit 1
    fi
done

if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "ERROR: nnU-Net Python is missing: $PYTHON_BIN"
    exit 1
fi
for metadata_file in dataset.json plans.json; do
    if [[ ! -f "${MODEL_DIR}/${metadata_file}" ]]; then
        echo "ERROR: Model metadata is missing: ${MODEL_DIR}/${metadata_file}"
        echo "Mount the nnUNet_results directory at /models or set nnUNet_results."
        exit 1
    fi
done

if [[ "$NNUNET_FOLDS" == "auto" ]]; then
    mapfile -t FOLDS < <(
        find "$MODEL_DIR" -mindepth 2 -maxdepth 2 -type f -path "*/fold_*/${NNUNET_CHECKPOINT}" \
            -printf '%h\n' | sed 's#.*/fold_##' | sort -n
    )
else
    read -r -a FOLDS <<< "${NNUNET_FOLDS//,/ }"
fi
if [[ "${#FOLDS[@]}" -eq 0 ]]; then
    echo "ERROR: No model folds were selected or discovered in $MODEL_DIR"
    exit 1
fi
for fold in "${FOLDS[@]}"; do
    if [[ ! -f "${MODEL_DIR}/fold_${fold}/${NNUNET_CHECKPOINT}" ]]; then
        echo "ERROR: Model checkpoint is missing: ${MODEL_DIR}/fold_${fold}/${NNUNET_CHECKPOINT}"
        exit 1
    fi
done

"$PYTHON_BIN" - "$MODEL_DIR" <<'PY'
import json
import sys
from pathlib import Path

import nibabel
import numpy
import torch
import nnunetv2

model_dir = Path(sys.argv[1])
plans = json.loads((model_dir / "plans.json").read_text())
dataset = json.loads((model_dir / "dataset.json").read_text())
if "3d_fullres" not in plans.get("configurations", {}):
    raise RuntimeError("Model plans do not contain the 3d_fullres configuration")
if int(dataset.get("numTraining", 0)) <= 0:
    raise RuntimeError("dataset.json has an invalid numTraining value")
print("PyTorch:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
print("nnU-Net/Python imports: OK")
PY

echo "Pipeline installation check passed."
echo "Model:  $MODEL_DIR"
echo "Folds:  ${FOLDS[*]}"
