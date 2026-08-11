# Knee MRI Quantitative Processing Pipeline

A containerised research pipeline for knee cartilage segmentation, DWI
preprocessing, tensor-derived diffusion metrics, T2-map preparation, and
cartilage-level T2/FA/MD extraction.

Version 1.4.0 contains five processing stages and does **not** run
tractography. It is intended for research use only and is not a medical device
or a substitute for independent quality control.

## Processing flow

1. Resolve BIDS-like inputs or explicit image-path overrides.
2. Segment the PD-weighted image with the Dataset501 five-fold nnU-Net model.
3. Run the preserved MRtrix/FSL DWI preprocessing and tensor calculation.
4. Copy the T2 map and resample the original prediction for inspection.
5. Extract T2, FA, and MD/ADC values from cartilage only.

The original nnU-Net prediction is retained. Quantitative masks are derived
from it independently for each metric grid; the source prediction is not
cleaned, relabelled, or replaced.

## Cartilage labels

Anatomical review of the trained model established the raw-label meaning below.
The historical `dataset.json` label names do not describe the trained masks
correctly, so `config/cartilage-labels.json` is authoritative for this
pipeline.

| Raw label | Reviewed anatomy | Quantitative action |
|---:|---|---|
| 1 | Femur bone | Excluded |
| 2 | Femoral cartilage | Automatically split into MFC/LFC |
| 3 | Tibia bone | Excluded |
| 4 | Medial tibial cartilage | Retained as MTC |
| 5 | Lateral tibial cartilage | Retained as LTC |

The femoral split is a world-space plane halfway between the medial and lateral
tibial-cartilage centroids. It adapts to image orientation and dimensions and
does not delete cartilage voxels.

| Analysis label | Region |
|---:|---|
| 201 | Medial femoral cartilage (MFC), derived from raw label 2 |
| 202 | Lateral femoral cartilage (LFC), derived from raw label 2 |
| 4 | Medial tibial cartilage (MTC), unchanged raw label 4 |
| 5 | Lateral tibial cartilage (LTC), unchanged raw label 5 |

## Model weights

Model checkpoints are not stored in Git or in the public container. Each fold
is approximately 247 MB. A complete runtime model directory must contain:

```text
Dataset501_KneeCartilage/
  nnUNetTrainer__nnUNetPlans__3d_fullres/
    dataset.json
    plans.json
    fold_0/checkpoint_final.pth
    fold_1/checkpoint_final.pth
    fold_2/checkpoint_final.pth
    fold_3/checkpoint_final.pth
    fold_4/checkpoint_final.pth
```

The public model record and its reuse licence must be approved before the model
is released. See `models/MODEL_CARD.md`, `models/checksums.sha256`, and
`RELEASE_CHECKLIST.md`. Mount an obtained model directory read-only at
`/models` and use `NNUNET_FOLDS=auto` for five-fold inference.

## Inputs

Automatic discovery expects one selected acquisition of each type:

```text
/data/sub-XXX/ses-1/anat/*_PDw.nii.gz
/data/sub-XXX/ses-1/dwi/*_dwi.nii.gz + .bval + .bvec + .json
/data/sub-XXX/ses-1/fmap/*_epi.nii.gz + .json
/data/derivatives/sub-XXX/**/*_T2map.nii.gz
```

Use `PD_RUN`, `DWI_RUN`, `EPI_RUN`, and `T2_RUN` when repeated acquisitions
exist. Explicit in-container paths are also supported with `PD_IMAGE`,
`DWI_IMAGE`, `DWI_BVAL`, `DWI_BVEC`, `DWI_JSON`, `REVERSE_EPI_IMAGE`,
`REVERSE_EPI_JSON`, `T2_MAP`, and `T2_REFERENCE_IMAGE`.

## Pull or build the container

After the GitHub v1.4.0 release is published and the GHCR package is made
public:

```bash
docker pull ghcr.io/valentinacamilleri/knee-mri-quantitative-pipeline:1.4.0
```

To build the code-only image locally:

```bash
docker build \
  --build-arg PIPELINE_VERSION=1.4.0 \
  -t knee-mri-quantitative-pipeline:1.4.0 .
```

The image targets `linux/amd64`. NVIDIA GPU execution requires a working host
driver and NVIDIA Container Toolkit. CPU segmentation is supported but is much
slower.

## Run one subject

```bash
docker run --rm --gpus all \
  --shm-size=8g \
  --user "$(id -u):$(id -g)" \
  -v /path/to/dataset:/data:ro \
  -v /path/to/nnUNet_results:/models:ro \
  -v /path/to/work:/work \
  -v /path/to/output:/output \
  -e HOME=/tmp \
  -e SESSION_ID=ses-1 \
  -e NNUNET_FOLDS=auto \
  -e NNUNET_DEVICE=cuda \
  -e NNUNET_NPP=1 \
  -e NNUNET_NPS=1 \
  -e NTHREADS=8 \
  -e READOUT_TIME=0.048 \
  -e T2_MAX=150 \
  -e MD_MAX=0.01 \
  ghcr.io/valentinacamilleri/knee-mri-quantitative-pipeline:1.4.0 \
  /pipeline/scripts/06_run_subject_pipeline.sh sub-001
```

For CPU inference, omit `--gpus all` and set `NNUNET_DEVICE=cpu`.

Validate commands, Python packages, model metadata, and selected checkpoints:

```bash
docker run --rm --gpus all \
  -v /path/to/nnUNet_results:/models:ro \
  ghcr.io/valentinacamilleri/knee-mri-quantitative-pipeline:1.4.0 \
  --check
```

## Outputs

Important per-subject outputs include:

```text
segmentation/sub-XXX_cartilage.nii.gz
dwi/sub-XXX_dwi_preprocessed.nii.gz
dwi/sub-XXX_dwi_preprocessed.bval
dwi/sub-XXX_dwi_preprocessed.bvec
diffusion_metrics/sub-XXX_FA.nii.gz
diffusion_metrics/sub-XXX_ADC.nii.gz
diffusion_metrics/sub-XXX_AD.nii.gz
diffusion_metrics/sub-XXX_RD.nii.gz
t2/sub-XXX_T2map.nii.gz
t2/sub-XXX_cartilage_in_T2_space.nii.gz
quantitative_analysis/sub-XXX_segment_statistics.csv
quantitative_analysis/sub-XXX_segment_voxel_values.csv.gz
quantitative_analysis/sub-XXX_extraction_metadata.json
```

MRtrix `tensor2metric -adc` produces the mean apparent diffusion coefficient,
also called mean diffusivity. The original output name is therefore retained as
`*_ADC.nii.gz`; this is the MD map used by quantitative analysis.

Validity rules are applied during extraction:

- T2: finite values satisfying `0 < T2 <= T2_MAX` (default 150)
- FA: finite values satisfying `0 < FA <= 1`
- MD/ADC: finite values satisfying `0 < MD <= MD_MAX` (default 0.01 mm²/s)

The metadata JSON records source paths, image geometry, automatic split
geometry, valid ranges, and included/excluded voxel counts.

## Apptainer

After pulling or converting the released OCI image, bind data, models, work,
and output:

```bash
apptainer exec --nv --cleanenv \
  --bind /path/to/dataset:/data:ro \
  --bind /path/to/nnUNet_results:/models:ro \
  --bind /path/to/work:/work \
  --bind /path/to/output:/output \
  knee-mri-quantitative-pipeline_1.4.0.sif \
  /pipeline/scripts/06_run_subject_pipeline.sh sub-001
```

## Reproducibility and validation

The release pins the MRtrix3 3.0.8 base-image digest, Miniforge installer,
Python version, pip version, PyTorch family, and Python package versions.
Run local release checks with:

```bash
bash scripts/release_checks.sh
```

The final five-stage configuration completed on 31 internal subjects. This is
an operational test, not an external segmentation-accuracy or clinical
validation study.

## Privacy, licensing, and citation

Do not place participant data, derivative images, outputs, or logs in this
repository. Users are responsible for de-identification, governance, and
independent output review.

The repository's original source code is MIT licensed. The container also
contains separately licensed third-party software, including FSL components
with non-commercial-use restrictions. The model weights require their own
explicit licence. See `THIRD_PARTY_NOTICES.md`, `LICENSE`, and
`models/MODEL_CARD.md` before redistribution or commercial use.

If using the pipeline, cite the repository metadata in `CITATION.cff` and the
relevant nnU-Net, MRtrix3, FSL, and ANTs publications.
