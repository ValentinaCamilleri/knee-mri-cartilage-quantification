#!/usr/bin/env bash
set -euo pipefail

SUBJECT="sub-001"
SESSION="ses-1"

DATA_ROOT="${DATA_ROOT:-/data}"
WORK_ROOT="${WORK_ROOT:-/work}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/output}"
NTHREADS="${NTHREADS:-8}"

INPUT_DWI_DIR="${DATA_ROOT}/${SUBJECT}/${SESSION}/dwi"
INPUT_FMAP_DIR="${DATA_ROOT}/${SUBJECT}/${SESSION}/fmap"
INPUT_ANAT_DIR="${DATA_ROOT}/${SUBJECT}/${SESSION}/anat"

DWI_AP_NIFTI="${INPUT_DWI_DIR}/${SUBJECT}_${SESSION}_dwi.nii.gz"
DWI_AP_BVEC="${INPUT_DWI_DIR}/${SUBJECT}_${SESSION}_dwi.bvec"
DWI_AP_BVAL="${INPUT_DWI_DIR}/${SUBJECT}_${SESSION}_dwi.bval"
DWI_AP_JSON="${INPUT_DWI_DIR}/${SUBJECT}_${SESSION}_dwi.json"

DWI_REVERSE_NIFTI="${INPUT_FMAP_DIR}/${SUBJECT}_${SESSION}_dir-LR_epi.nii.gz"
DWI_REVERSE_BVEC="${INPUT_FMAP_DIR}/${SUBJECT}_${SESSION}_dir-LR_epi.bvec"
DWI_REVERSE_BVAL="${INPUT_FMAP_DIR}/${SUBJECT}_${SESSION}_dir-LR_epi.bval"
DWI_REVERSE_JSON="${INPUT_FMAP_DIR}/${SUBJECT}_${SESSION}_dir-LR_epi.json"

PD_NIFTI="${INPUT_ANAT_DIR}/${SUBJECT}_${SESSION}_PDw.nii.gz"

WORK_DIR="${WORK_ROOT}/${SUBJECT}/legacy_dwi_pipeline"
FINAL_DIR="${OUTPUT_ROOT}/${SUBJECT}/legacy_dwi_pipeline"
LOG_FILE="${FINAL_DIR}/${SUBJECT}_legacy_pipeline.log"

# Subject-specific values obtained from the JSON metadata.
PE_DIR="i"
REVERSE_PE_DIR="i-"
READOUT_TIME="0.0474008"

for required_file in \
    "$DWI_AP_NIFTI" \
    "$DWI_AP_BVEC" \
    "$DWI_AP_BVAL" \
    "$DWI_AP_JSON" \
    "$DWI_REVERSE_NIFTI" \
    "$DWI_REVERSE_BVEC" \
    "$DWI_REVERSE_BVAL" \
    "$DWI_REVERSE_JSON" \
    "$PD_NIFTI"
do
    if [[ ! -f "$required_file" ]]; then
        echo "ERROR: Required input file not found:"
        echo "$required_file"
        exit 1
    fi
done

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$FINAL_DIR"

exec > >(tee "$LOG_FILE") 2>&1

cd "$WORK_DIR"

echo "=================================================="
echo "Legacy DWI pipeline"
echo "=================================================="
echo "Subject:            $SUBJECT"
echo "Main PE direction:  $PE_DIR"
echo "Reverse direction:  $REVERSE_PE_DIR"
echo "Readout time:       $READOUT_TIME seconds"
echo "Work directory:     $WORK_DIR"
echo "Output directory:   $FINAL_DIR"
echo

echo "[1/10] Converting NIfTI inputs to MIF"

mrconvert \
    "$DWI_AP_NIFTI" \
    dwi_AP.mif \
    -fslgrad "$DWI_AP_BVEC" "$DWI_AP_BVAL" \
    -json_import "$DWI_AP_JSON" \
    -force

# This is the reverse phase-encoded EPI acquisition. It is named
# dwi_PA.mif here only to reproduce the naming of the old workflow.
mrconvert \
    "$DWI_REVERSE_NIFTI" \
    dwi_PA.mif \
    -fslgrad "$DWI_REVERSE_BVEC" "$DWI_REVERSE_BVAL" \
    -json_import "$DWI_REVERSE_JSON" \
    -force

mrconvert \
    "$PD_NIFTI" \
    pd.mif \
    -force

echo "[2/10] Denoising and Gibbs correction"

dwidenoise \
    dwi_AP.mif \
    dwi_AP_den.mif \
    -nthreads "$NTHREADS" \
    -force

mrdegibbs \
    dwi_AP_den.mif \
    dwi_AP_clean.mif \
    -nthreads "$NTHREADS" \
    -force

dwidenoise \
    dwi_PA.mif \
    dwi_PA_den.mif \
    -nthreads "$NTHREADS" \
    -force

mrdegibbs \
    dwi_PA_den.mif \
    dwi_PA_clean.mif \
    -nthreads "$NTHREADS" \
    -force

echo "[3/10] Extracting b=0 volumes"

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

echo "[4/10] Creating reversed phase-encoding b=0 pair"

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

# Retained for comparison with the old workflow.
# The current subject uses i followed by i-, corresponding to:
printf "1 0 0 %s\n-1 0 0 %s\n" \
    "$READOUT_TIME" \
    "$READOUT_TIME" \
    > acqparams.txt

echo "[5/10] Running TOPUP and eddy through dwifslpreproc"

dwifslpreproc \
    dwi_AP_clean.mif \
    dwi_preproc.mif \
    -rpe_pair \
    -se_epi b0_pair.nii.gz \
    -pe_dir "$PE_DIR" \
    -readout_time "$READOUT_TIME" \
    -eddy_options " --repol" \
    -scratch "$WORK_DIR/dwifslpreproc_scratch" \
    -nthreads "$NTHREADS" \
    -force

echo "[6/10] Creating corrected mean b=0 image"

dwiextract \
    dwi_preproc.mif \
    - \
    -bzero |
mrmath \
    - \
    mean \
    b0_mean.mif \
    -axis 3 \
    -nthreads "$NTHREADS" \
    -force

echo "[7/10] Registering PD image to corrected DWI"

mrregister \
    pd.mif \
    b0_mean.mif \
    -type rigid \
    -rigid pd2dwi.txt \
    -transformed pd_in_dwi.mif \
    -nthreads "$NTHREADS" \
    -force

echo "[8/10] Creating the PD-derived analysis mask"

mrcalc \
    pd_in_dwi.mif \
    20 \
    -gt \
    pd_mask_raw.mif \
    -force

maskfilter \
    pd_mask_raw.mif \
    dilate \
    pd_mask_dilated.mif \
    -npass 1 \
    -nthreads "$NTHREADS" \
    -force

maskfilter \
    pd_mask_dilated.mif \
    connect \
    pd_mask_clean.mif \
    -largest \
    -nthreads "$NTHREADS" \
    -force

maskfilter \
    pd_mask_clean.mif \
    erode \
    pd_mask_final.mif \
    -npass 1 \
    -nthreads "$NTHREADS" \
    -force

# The registered PD image is already in DWI space, so the registration
# transform must not be applied to the mask a second time.
mrgrid \
    pd_mask_final.mif \
    regrid \
    pd_mask_dwi.mif \
    -template dwi_preproc.mif \
    -interp nearest \
    -datatype uint8 \
    -force

echo "[9/10] Fitting the tensor and calculating metrics"

dwi2tensor \
    dwi_preproc.mif \
    tensor.mif \
    -mask pd_mask_dwi.mif \
    -nthreads "$NTHREADS" \
    -force

tensor2metric \
    tensor.mif \
    -fa fa.mif \
    -adc adc.mif \
    -ad ad.mif \
    -rd rd.mif \
    -mask pd_mask_dwi.mif \
    -nthreads "$NTHREADS" \
    -force

echo "[10/10] Applying the old FA upper-limit correction and exporting"

# This reproduces the old procedure: values above 1 are set to 1.
mrcalc \
    fa.mif \
    1 \
    -min \
    fa_fixed.mif \
    -force

mrconvert \
    dwi_preproc.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_dwi_preprocessed.nii.gz" \
    -export_grad_fsl \
        "$FINAL_DIR/${SUBJECT}_legacy_dwi_preprocessed.bvec" \
        "$FINAL_DIR/${SUBJECT}_legacy_dwi_preprocessed.bval" \
    -force

mrconvert \
    b0_mean.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_mean_b0.nii.gz" \
    -force

mrconvert \
    pd_in_dwi.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_pd_in_dwi.nii.gz" \
    -force

mrconvert \
    pd_mask_dwi.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_mask.nii.gz" \
    -datatype uint8 \
    -force

mrconvert \
    fa_fixed.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_FA.nii.gz" \
    -force

mrconvert \
    adc.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_ADC.nii.gz" \
    -force

mrconvert \
    ad.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_AD.nii.gz" \
    -force

mrconvert \
    rd.mif \
    "$FINAL_DIR/${SUBJECT}_legacy_RD.nii.gz" \
    -force

cp pd2dwi.txt "$FINAL_DIR/${SUBJECT}_legacy_pd2dwi.txt"
cp acqparams.txt "$FINAL_DIR/${SUBJECT}_legacy_acqparams.txt"

cat > "$FINAL_DIR/${SUBJECT}_legacy_manifest.txt" <<MANIFEST
subject=$SUBJECT
pd=$PD_NIFTI
main_dwi=$DWI_AP_NIFTI
reverse_epi=$DWI_REVERSE_NIFTI
phase_encoding_direction=$PE_DIR
reverse_phase_encoding_direction=$REVERSE_PE_DIR
total_readout_time=$READOUT_TIME
fa_correction=upper_limit_only
processed_on=$(date '+%F %T')
MANIFEST

echo
echo "=================================================="
echo "Legacy DWI pipeline completed successfully"
echo "=================================================="
echo "Outputs:"
echo "$FINAL_DIR/${SUBJECT}_legacy_FA.nii.gz"
echo "$FINAL_DIR/${SUBJECT}_legacy_ADC.nii.gz"
echo "$FINAL_DIR/${SUBJECT}_legacy_AD.nii.gz"
echo "$FINAL_DIR/${SUBJECT}_legacy_RD.nii.gz"
echo "$FINAL_DIR/${SUBJECT}_legacy_mask.nii.gz"
echo "$FINAL_DIR/${SUBJECT}_legacy_dwi_preprocessed.nii.gz"
