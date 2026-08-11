# Dataset501 Knee Cartilage nnU-Net model card

## Status

Model publication is pending provenance, governance, and licence approval. The
five checkpoints are not included in this Git repository or in the public
container image. Until an explicit model licence and archival download record
are added, this document does not grant permission to redistribute the weights.

## Model summary

- Framework: nnU-Net v2 2.5.2
- Configuration: `3d_fullres`
- Trainer/plans: `nnUNetTrainer__nnUNetPlans`
- Input channel: one MRI volume, used by the pipeline as a PD-weighted knee MRI
- Ensemble: five cross-validation folds, numbered 0 through 4
- Checkpoint: `checkpoint_final.pth` for each fold
- Dataset metadata: `Dataset501_KneeCartilage`, reporting 404 training cases
- Tested inference stack: Python 3.9.23, PyTorch 2.8.0, CUDA 12.8 wheels

## Anatomical label interpretation

The historical `dataset.json` names do not match anatomical review of the
trained predictions. The reviewed runtime interpretation is:

| Raw label | Reviewed anatomy | Analysis use |
|---:|---|---|
| 0 | Background | Excluded |
| 1 | Femur bone | Excluded |
| 2 | Femoral cartilage | Split into MFC/LFC |
| 3 | Tibia bone | Excluded |
| 4 | Medial tibial cartilage | Retained |
| 5 | Lateral tibial cartilage | Retained |

`config/cartilage-labels.json` is authoritative for downstream quantitative
analysis. Raw prediction labels are retained unchanged on disk.

## Intended use

The model is intended for research segmentation of knee MRI with acquisition
characteristics sufficiently similar to the training data. The surrounding
pipeline uses its cartilage prediction to extract T2, FA, and MD/ADC values.
Every segmentation and registration must undergo independent quality control.

## Out-of-scope use

- Clinical diagnosis, treatment selection, or unsupervised clinical reporting
- Use as a medical device
- Anatomies, contrasts, field strengths, pathologies, or populations not shown
  to be represented by the training and validation data
- Quantification without reviewing segmentation and registration quality

## Current validation evidence

The five-fold ensemble ran successfully as part of the final pipeline on 31
internal subjects and generated the expected outputs. This is operational
validation only. A release-ready external accuracy analysis, subgroup analysis,
failure analysis, and comparison against independent reference annotations are
not documented here and must not be inferred from successful execution.

## Known limitations

- Training-data provenance and representativeness are not yet documented in a
  public release-ready record.
- The historical dataset label names are incorrect for this trained model.
- Domain shift can cause plausible-looking but incorrect segmentations.
- The automatic femoral split is anatomical post-processing, not an additional
  learned output.
- Small compartments are sensitive to registration and DWI resolution.
- No guarantee of generalisation or clinical performance is provided.

## Required model package

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

Verify the files with `models/checksums.sha256`. The eventual archival record
must preserve this directory layout and state its model licence explicitly.

## Training-data documentation required before publication

The responsible author must add the data source, cohort description, inclusion
and exclusion criteria, MRI acquisition characteristics, annotation protocol,
annotator expertise, quality-control process, split methodology, ethics/consent
basis, and any restrictions inherited from the source dataset.

## Citation

Users must cite the pipeline release, the eventual model DOI, and nnU-Net:

Isensee, F., Jaeger, P. F., Kohl, S. A., Petersen, J., & Maier-Hein, K. H.
(2021). nnU-Net: a self-configuring method for deep learning-based biomedical
image segmentation. *Nature Methods*, 18, 203–211.
