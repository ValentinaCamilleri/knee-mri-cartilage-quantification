#!/usr/bin/env bash
set -euo pipefail

WORK_ROOT="${WORK_ROOT:-/work}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/output}"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 sub-XXX"
    exit 1
fi

SUBJECT="$1"

T2_MAP="${WORK_ROOT}/${SUBJECT}/input/t2map.nii.gz"
SEGMENTATION="${OUTPUT_ROOT}/${SUBJECT}/segmentation/${SUBJECT}_cartilage.nii.gz"

T2_OUTPUT="${OUTPUT_ROOT}/${SUBJECT}/t2"

T2_COPY="${T2_OUTPUT}/${SUBJECT}_T2map.nii.gz"
SEGMENTATION_T2="${T2_OUTPUT}/${SUBJECT}_cartilage_in_T2_space.nii.gz"

for required_file in \
    "$T2_MAP" \
    "$SEGMENTATION"
do
    if [[ ! -e "$required_file" ]]; then
        echo "ERROR: Required file not found:"
        echo "$required_file"
        exit 1
    fi
done

mkdir -p "$T2_OUTPUT"

echo "========================================"
echo "Preparing T2-map outputs"
echo "========================================"
echo "Subject:       $SUBJECT"
echo "T2 map:        $T2_MAP"
echo "Segmentation:  $SEGMENTATION"
echo

echo "[1/3] Copying the T2 map"

mrconvert \
    "$T2_MAP" \
    "$T2_COPY" \
    -force

echo "[2/3] Resampling the segmentation onto the T2-map grid"

mrgrid \
    "$SEGMENTATION" \
    regrid \
    "$SEGMENTATION_T2" \
    -template "$T2_MAP" \
    -interp nearest \
    -datatype uint8 \
    -force

echo "[3/3] Verifying output geometry"

T2_SIZE="$(mrinfo "$T2_COPY" -size)"
SEG_SIZE="$(mrinfo "$SEGMENTATION_T2" -size)"

T2_SPACING="$(mrinfo "$T2_COPY" -spacing)"
SEG_SPACING="$(mrinfo "$SEGMENTATION_T2" -spacing)"

if [[ "$T2_SIZE" != "$SEG_SIZE" ]]; then
    echo "ERROR: T2 map and segmentation matrix sizes differ."
    echo "T2:           $T2_SIZE"
    echo "Segmentation: $SEG_SIZE"
    exit 1
fi

if [[ "$T2_SPACING" != "$SEG_SPACING" ]]; then
    echo "ERROR: T2 map and segmentation voxel sizes differ."
    echo "T2:           $T2_SPACING"
    echo "Segmentation: $SEG_SPACING"
    exit 1
fi

echo
echo "T2 preparation completed successfully."
echo
echo "Matrix size:  $T2_SIZE"
echo "Voxel size:   $T2_SPACING"
echo
echo "Outputs:"
echo "$T2_COPY"
echo "$SEGMENTATION_T2"
