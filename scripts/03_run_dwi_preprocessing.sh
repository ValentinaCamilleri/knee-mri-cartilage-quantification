#!/usr/bin/env bash
set -euo pipefail

WORK_ROOT="${WORK_ROOT:-/work}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/output}"
NTHREADS="${NTHREADS:-8}"
PD_THRESHOLD="${PD_THRESHOLD:-20}"
READOUT_TIME="${READOUT_TIME:-0.048}"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 sub-XXX"
    exit 1
fi

SUBJECT="$1"

# ==============================================================================
# DWI PIPELINE USING DRUM NIfTI INPUTS WITH FORCED DICOM-LIKE STRIDES
# ==============================================================================

INPUT_DIR="${WORK_ROOT}/${SUBJECT}/input"
WORK_DIR="${WORK_ROOT}/${SUBJECT}/dwi_processing"

DWI_OUTPUT="${OUTPUT_ROOT}/${SUBJECT}/dwi"
METRICS_OUTPUT="${OUTPUT_ROOT}/${SUBJECT}/diffusion_metrics"
SEGMENTATION_DIR="${OUTPUT_ROOT}/${SUBJECT}/segmentation"

DWI_AP_IMG="${INPUT_DIR}/dwi_AP.nii.gz"
DWI_AP_BVEC="${INPUT_DIR}/dwi_AP.bvec"
DWI_AP_BVAL="${INPUT_DIR}/dwi_AP.bval"
DWI_AP_JSON="${INPUT_DIR}/dwi_AP.json"

DWI_PA_IMG="${INPUT_DIR}/dwi_reverse.nii.gz"
DWI_PA_BVEC="${INPUT_DIR}/dwi_reverse.bvec"
DWI_PA_BVAL="${INPUT_DIR}/dwi_reverse.bval"
DWI_PA_JSON="${INPUT_DIR}/dwi_reverse.json"

PD_IMG="${INPUT_DIR}/pd.nii.gz"
SEGMENTATION="${SEGMENTATION_DIR}/${SUBJECT}_cartilage.nii.gz"

for required_file in \
    "$DWI_AP_IMG" \
    "$DWI_AP_BVEC" \
    "$DWI_AP_BVAL" \
    "$DWI_AP_JSON" \
    "$DWI_PA_IMG" \
    "$DWI_PA_BVEC" \
    "$DWI_PA_BVAL" \
    "$DWI_PA_JSON" \
    "$PD_IMG"
do
    if [[ ! -e "$required_file" ]]; then
        echo "ERROR: Required input not found:"
        echo "$required_file"
        exit 1
    fi
done

mkdir -p \
    "$WORK_DIR" \
    "$DWI_OUTPUT" \
    "$METRICS_OUTPUT"

cd "$WORK_DIR"

export OMP_NUM_THREADS="$NTHREADS"

echo "=================================================="
echo "DWI processing with forced DICOM-like strides"
echo "=================================================="
echo "Subject:       $SUBJECT"
echo "Input folder:  $INPUT_DIR"
echo "Readout time:  $READOUT_TIME"
echo "Threads:       $NTHREADS"
echo

# ==============================================================================
# 1. CONVERT DRUM NIfTI INPUTS TO MIF
# ==============================================================================

echo "[1/8] Converting DrUM NIfTI inputs to MIF with strides 3,-1,-2,4"

# Forcing strides to 3,-1,-2,4 flips the image matrix array to match DICOM-like orientation.

mrconvert \
    "$DWI_AP_IMG" \
    dwi_AP.mif \
    -fslgrad "$DWI_AP_BVEC" "$DWI_AP_BVAL" \
    -json_import "$DWI_AP_JSON" \
    -strides 3,-1,-2,4 \
    -force

mrconvert \
    "$DWI_PA_IMG" \
    dwi_PA.mif \
    -fslgrad "$DWI_PA_BVEC" "$DWI_PA_BVAL" \
    -json_import "$DWI_PA_JSON" \
    -strides 3,-1,-2,4 \
    -force

mrconvert \
    "$PD_IMG" \
    pd.mif \
    -force

# ==============================================================================
# 2. DENOISE + GIBBS RINGING CORRECTION
# ==============================================================================

echo "[2/8] Denoising and Gibbs-ringing correction"

dwidenoise \
    dwi_AP.mif \
    dwi_AP_clean.mif \
    -nthreads "$NTHREADS" \
    -force

mrdegibbs \
    dwi_AP_clean.mif \
    dwi_AP_clean.mif \
    -nthreads "$NTHREADS" \
    -force

dwidenoise \
    dwi_PA.mif \
    dwi_PA_clean.mif \
    -nthreads "$NTHREADS" \
    -force

mrdegibbs \
    dwi_PA_clean.mif \
    dwi_PA_clean.mif \
    -nthreads "$NTHREADS" \
    -force

# ==============================================================================
# 3. EXTRACT B0 VOLUMES AND CREATE PAIR FOR TOPUP
# ==============================================================================

echo "[3/8] Extracting AP and PA b0 volumes and creating TOPUP pair"

dwiextract \
    dwi_AP_clean.mif \
    b0_AP.mif \
    -bzero \
    -force

dwiextract \
    dwi_PA_clean.mif \
    b0_PA.mif \
    -bzero \
    -force

mrmath \
    b0_AP.mif \
    mean \
    b0_AP_mean.mif \
    -axis 3 \
    -nthreads "$NTHREADS" \
    -force

mrmath \
    b0_PA.mif \
    mean \
    b0_PA_mean.mif \
    -axis 3 \
    -nthreads "$NTHREADS" \
    -force

mrcat \
    b0_AP_mean.mif \
    b0_PA_mean.mif \
    b0_pair.mif \
    -axis 3 \
    -force

mrconvert \
    b0_pair.mif \
    b0_pair.nii.gz \
    -force

# ==============================================================================
# 4. CREATE ACQPARAMS FILE
# ==============================================================================

echo "[4/8] Creating acqparams.txt"

printf "0 -1 0 ${READOUT_TIME}\n0 1 0 ${READOUT_TIME}\n" > acqparams.txt

# ==============================================================================
# 5. PREPROCESSING: TOPUP + EDDY
# ==============================================================================

echo "[5/8] Running TOPUP and eddy correction"

# This follows the requested AP/PA workflow.
# The b0 pair is supplied explicitly and the main DWI is dwi_AP_clean.mif.

dwifslpreproc \
    dwi_AP_clean.mif \
    dwi_preproc.mif \
    -rpe_pair \
    -se_epi b0_pair.nii.gz \
    -pe_dir AP \
    -readout_time "$READOUT_TIME" \
    -eddy_options " --repol" \
    -eddyqc_all "${WORK_DIR}/eddy_qc" \
    -scratch "${WORK_DIR}/dwifslpreproc_scratch" \
    -nthreads "$NTHREADS" \
    -force

# Save a bias-corrected copy for tractography.
# Tensor fitting below follows your supplied script and uses dwi_preproc.mif.

echo "[5b/8] Applying ANTs bias-field correction for tractography output"

dwibiascorrect ants \
    dwi_preproc.mif \
    dwi_bias.mif \
    -nthreads "$NTHREADS" \
    -force

# ==============================================================================
# 6. CREATE CARTILAGE MASK FROM PD
# ==============================================================================

echo "[6/8] Registering PD to DWI and creating PD-derived DWI mask"

dwiextract \
    dwi_preproc.mif \
    -bzero \
    - |
mrmath \
    - \
    mean \
    b0_mean.mif \
    -axis 3 \
    -nthreads "$NTHREADS" \
    -force

mrregister \
    pd.mif \
    b0_mean.mif \
    -type rigid \
    -rigid pd2dwi.txt \
    -nthreads "$NTHREADS" \
    -force

# Crucial fix: resampling to the b0_mean.mif template grid.

mrtransform \
    pd.mif \
    pd_in_dwi.mif \
    -linear pd2dwi.txt \
    -template b0_mean.mif \
    -force

mrcalc \
    pd_in_dwi.mif \
    "$PD_THRESHOLD" \
    -gt \
    pd_mask_raw.mif \
    -force

maskfilter \
    pd_mask_raw.mif \
    dilate \
    pd_mask_dilated.mif \
    -nthreads "$NTHREADS" \
    -force

maskfilter \
    pd_mask_dilated.mif \
    connect \
    pd_mask_clean.mif \
    -largest \
    -nthreads "$NTHREADS" \
    -force

# Transform the nnU-Net segmentation into DWI space for downstream extraction.

if [[ -f "$SEGMENTATION" ]]; then
    mrtransform \
        "$SEGMENTATION" \
        cartilage_in_dwi.nii.gz \
        -linear pd2dwi.txt \
        -template b0_mean.mif \
        -interp nearest \
        -datatype uint8 \
        -force
else
    echo "WARNING: Segmentation not found:"
    echo "$SEGMENTATION"
    echo "DWI metrics will still be created."
fi

# ==============================================================================
# 7. TENSOR FITTING & METRIC EXTRACTION
# ==============================================================================

echo "[7/8] Tensor fitting and metric extraction"

dwi2tensor \
    dwi_preproc.mif \
    tensor.mif \
    -mask pd_mask_clean.mif \
    -nthreads "$NTHREADS" \
    -force

tensor2metric \
    tensor.mif \
    -fa fa.mif \
    -adc adc.mif \
    -ad ad.mif \
    -rd rd.mif \
    -nthreads "$NTHREADS" \
    -force

mrcalc \
    fa.mif \
    1 \
    -min \
    fa_fixed.mif \
    -force

# ==============================================================================
# 8. SAVE OUTPUTS FOR THE ORIGINAL DOCKER PIPELINE
# ==============================================================================

echo "[8/8] Saving final outputs"

mrconvert \
    dwi_preproc.mif \
    "${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.nii.gz" \
    -export_grad_fsl \
        "${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.bvec" \
        "${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.bval" \
    -force

mrconvert \
    dwi_preproc.mif \
    "${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.mif" \
    -force

mrconvert \
    dwi_bias.mif \
    "${DWI_OUTPUT}/${SUBJECT}_dwi_biascorrected.mif" \
    -force

mrconvert \
    b0_mean.mif \
    "${DWI_OUTPUT}/${SUBJECT}_mean_b0_preprocessed.nii.gz" \
    -force

mrconvert \
    pd_in_dwi.mif \
    "${METRICS_OUTPUT}/${SUBJECT}_pd_in_dwi.nii.gz" \
    -force

mrconvert \
    pd_mask_clean.mif \
    "${METRICS_OUTPUT}/${SUBJECT}_dwi_mask.nii.gz" \
    -datatype uint8 \
    -force

mrconvert \
    fa_fixed.mif \
    "${METRICS_OUTPUT}/${SUBJECT}_FA.nii.gz" \
    -force

mrconvert \
    adc.mif \
    "${METRICS_OUTPUT}/${SUBJECT}_ADC.nii.gz" \
    -force

mrconvert \
    ad.mif \
    "${METRICS_OUTPUT}/${SUBJECT}_AD.nii.gz" \
    -force

mrconvert \
    rd.mif \
    "${METRICS_OUTPUT}/${SUBJECT}_RD.nii.gz" \
    -force

cp -f \
    pd2dwi.txt \
    "${METRICS_OUTPUT}/${SUBJECT}_pd_to_dwi_rigid.txt"

cp -f \
    acqparams.txt \
    "${DWI_OUTPUT}/acqparams.txt"

cat > "${DWI_OUTPUT}/dwi_pipeline_report.txt" <<REPORT
Subject: ${SUBJECT}

Pipeline:
DrUM NIfTI inputs were converted to MRtrix MIF using forced strides:
-strides 3,-1,-2,4

Main DWI input:
${DWI_AP_IMG}

Reverse phase-encoded input:
${DWI_PA_IMG}

PD input:
${PD_IMG}

TOPUP/eddy:
dwifslpreproc dwi_AP_clean.mif dwi_preproc.mif -rpe_pair -se_epi b0_pair.nii.gz -pe_dir AP -readout_time ${READOUT_TIME} -eddy_options " --repol"

acqparams.txt:
0 -1 0 ${READOUT_TIME}
0 1 0 ${READOUT_TIME}

Outputs:
${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.nii.gz
${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.mif
${DWI_OUTPUT}/${SUBJECT}_dwi_biascorrected.mif
${DWI_OUTPUT}/${SUBJECT}_mean_b0_preprocessed.nii.gz
${METRICS_OUTPUT}/${SUBJECT}_dwi_mask.nii.gz
${METRICS_OUTPUT}/${SUBJECT}_FA.nii.gz
${METRICS_OUTPUT}/${SUBJECT}_ADC.nii.gz
${METRICS_OUTPUT}/${SUBJECT}_AD.nii.gz
${METRICS_OUTPUT}/${SUBJECT}_RD.nii.gz
REPORT

if [[ -f cartilage_in_dwi.nii.gz ]]; then
    cp -f \
        cartilage_in_dwi.nii.gz \
        "${METRICS_OUTPUT}/${SUBJECT}_cartilage_in_dwi.nii.gz"
fi

echo
echo "=================================================="
echo "DWI pipeline completed successfully"
echo "=================================================="
echo "Subject: $SUBJECT"
echo
echo "Main outputs:"
echo "${DWI_OUTPUT}/${SUBJECT}_dwi_preprocessed.nii.gz"
echo "${DWI_OUTPUT}/${SUBJECT}_dwi_biascorrected.mif"
echo "${METRICS_OUTPUT}/${SUBJECT}_dwi_mask.nii.gz"
echo "${METRICS_OUTPUT}/${SUBJECT}_FA.nii.gz"
echo "${METRICS_OUTPUT}/${SUBJECT}_ADC.nii.gz"
echo "${DWI_OUTPUT}/dwi_pipeline_report.txt"
