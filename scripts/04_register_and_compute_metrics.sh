#!/usr/bin/env bash
set -euo pipefail

WORK_ROOT="${WORK_ROOT:-/work}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/output}"
NTHREADS="${NTHREADS:-8}"
PD_THRESHOLD="${PD_THRESHOLD:-20}"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 sub-XXX"
    exit 1
fi

SUBJECT="$1"

PD_IMAGE="${WORK_ROOT}/${SUBJECT}/input/pd.nii.gz"

SEGMENTATION="${OUTPUT_ROOT}/${SUBJECT}/segmentation/${SUBJECT}_cartilage.nii.gz"

DWI_DIR="${OUTPUT_ROOT}/${SUBJECT}/dwi"
DWI_IMAGE="${DWI_DIR}/${SUBJECT}_dwi_preprocessed.mif"
MEAN_B0="${DWI_DIR}/${SUBJECT}_mean_b0_preprocessed.nii.gz"

REG_WORK="${WORK_ROOT}/${SUBJECT}/registration"
METRICS_OUTPUT="${OUTPUT_ROOT}/${SUBJECT}/diffusion_metrics"

TRANSFORM="${REG_WORK}/${SUBJECT}_pd_to_dwi_rigid.txt"
PD_IN_DWI="${REG_WORK}/${SUBJECT}_pd_in_dwi.nii.gz"
SEGMENTATION_IN_DWI="${REG_WORK}/${SUBJECT}_cartilage_in_dwi.nii.gz"

MASK_THRESHOLD="${REG_WORK}/${SUBJECT}_mask_threshold.mif"
MASK_DILATED="${REG_WORK}/${SUBJECT}_mask_dilated.mif"
MASK_CONNECTED="${REG_WORK}/${SUBJECT}_mask_connected.mif"
MASK_FINAL="${REG_WORK}/${SUBJECT}_dwi_mask.mif"

TENSOR="${REG_WORK}/${SUBJECT}_tensor.mif"
FA_RAW="${REG_WORK}/${SUBJECT}_FA_raw.mif"

for required_file in \
    "$PD_IMAGE" \
    "$SEGMENTATION" \
    "$DWI_IMAGE" \
    "$MEAN_B0"
do
    if [[ ! -e "$required_file" ]]; then
        echo "ERROR: Required file not found:"
        echo "$required_file"
        exit 1
    fi
done

mkdir -p \
    "$REG_WORK" \
    "$METRICS_OUTPUT"

echo "========================================"
echo "Registration and tensor metrics"
echo "========================================"
echo "Subject:        $SUBJECT"
echo "PD threshold:   $PD_THRESHOLD"
echo "Threads:        $NTHREADS"
echo

echo "[1/8] Registering PD image to corrected mean b=0"

mrregister \
    "$PD_IMAGE" \
    "$MEAN_B0" \
    -type rigid \
    -rigid "$TRANSFORM" \
    -transformed "$PD_IN_DWI" \
    -nthreads "$NTHREADS" \
    -force

echo "[2/8] Transforming cartilage segmentation into DWI space"

mrtransform \
    "$SEGMENTATION" \
    "$SEGMENTATION_IN_DWI" \
    -linear "$TRANSFORM" \
    -template "$MEAN_B0" \
    -interp nearest \
    -datatype uint8 \
    -force

echo "[3/8] Thresholding the registered PD image"

mrthreshold \
    "$PD_IN_DWI" \
    "$MASK_THRESHOLD" \
    -abs "$PD_THRESHOLD" \
    -force

echo "[4/8] Dilating the threshold mask"

maskfilter \
    "$MASK_THRESHOLD" \
    dilate \
    "$MASK_DILATED" \
    -npass 1 \
    -nthreads "$NTHREADS" \
    -force

echo "[5/8] Retaining the largest connected component"

maskfilter \
    "$MASK_DILATED" \
    connect \
    "$MASK_CONNECTED" \
    -largest \
    -nthreads "$NTHREADS" \
    -force

echo "[6/8] Eroding the connected mask"

maskfilter \
    "$MASK_CONNECTED" \
    erode \
    "$MASK_FINAL" \
    -npass 1 \
    -nthreads "$NTHREADS" \
    -force

echo "[7/8] Fitting the diffusion tensor"

dwi2tensor \
    "$DWI_IMAGE" \
    "$TENSOR" \
    -mask "$MASK_FINAL" \
    -nthreads "$NTHREADS" \
    -force

echo "[8/8] Generating FA, ADC, AD and RD maps"

tensor2metric \
    "$TENSOR" \
    -mask "$MASK_FINAL" \
    -fa "$FA_RAW" \
    -adc "$METRICS_OUTPUT/${SUBJECT}_ADC.nii.gz" \
    -ad "$METRICS_OUTPUT/${SUBJECT}_AD.nii.gz" \
    -rd "$METRICS_OUTPUT/${SUBJECT}_RD.nii.gz" \
    -nthreads "$NTHREADS" \
    -force

# Restrict FA to its physically meaningful range of 0 to 1.
mrcalc \
    "$FA_RAW" \
    0 \
    -max \
    1 \
    -min \
    "$METRICS_OUTPUT/${SUBJECT}_FA.nii.gz" \
    -force

mrconvert \
    "$MASK_FINAL" \
    "$METRICS_OUTPUT/${SUBJECT}_dwi_mask.nii.gz" \
    -datatype uint8 \
    -force

cp \
    "$PD_IN_DWI" \
    "$METRICS_OUTPUT/${SUBJECT}_pd_in_dwi.nii.gz"

cp \
    "$SEGMENTATION_IN_DWI" \
    "$METRICS_OUTPUT/${SUBJECT}_cartilage_in_dwi.nii.gz"

cp \
    "$TRANSFORM" \
    "$METRICS_OUTPUT/${SUBJECT}_pd_to_dwi_rigid.txt"

echo
echo "Registration and tensor fitting completed successfully."
echo
echo "Outputs:"
echo "$METRICS_OUTPUT/${SUBJECT}_pd_in_dwi.nii.gz"
echo "$METRICS_OUTPUT/${SUBJECT}_cartilage_in_dwi.nii.gz"
echo "$METRICS_OUTPUT/${SUBJECT}_dwi_mask.nii.gz"
echo "$METRICS_OUTPUT/${SUBJECT}_FA.nii.gz"
echo "$METRICS_OUTPUT/${SUBJECT}_ADC.nii.gz"
echo "$METRICS_OUTPUT/${SUBJECT}_AD.nii.gz"
echo "$METRICS_OUTPUT/${SUBJECT}_RD.nii.gz"
