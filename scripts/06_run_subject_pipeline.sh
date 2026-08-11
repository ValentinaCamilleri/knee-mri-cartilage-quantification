#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 sub-XXX"
    exit 1
fi

SUBJECT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "Knee MRI processing pipeline"
echo "=================================================="
echo "Subject: $SUBJECT"
echo

echo "Stage 1/5: Preparing inputs"
"$SCRIPT_DIR/01_prepare_inputs.sh" "$SUBJECT"

echo
echo "Stage 2/5: Running segmentation"
"$SCRIPT_DIR/02_run_segmentation.sh" "$SUBJECT"

echo
echo "Stage 3/5: Full DWI preprocessing and tensor metrics"
"$SCRIPT_DIR/03_run_dwi_preprocessing.sh" "$SUBJECT"

echo
echo "Stage 4/5: Preparing T2 outputs"
"$SCRIPT_DIR/05_prepare_t2_outputs.sh" "$SUBJECT"

echo
echo "Stage 5/5: Extracting segment-level values"
"$SCRIPT_DIR/07_extract_segment_values.sh" "$SUBJECT"

echo
echo "=================================================="
echo "Pipeline completed successfully"
echo "=================================================="
echo "Subject: $SUBJECT"
echo "Outputs: ${OUTPUT_ROOT:-/output}/${SUBJECT}"
