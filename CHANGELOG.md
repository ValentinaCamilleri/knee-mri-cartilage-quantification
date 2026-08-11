# Changelog

All notable changes to this project are documented here.

## [1.4.0] - 2026-08-11

### Added

- Five-fold nnU-Net inference selection with `NNUNET_FOLDS=auto`.
- Explicit input-path overrides and repeated-acquisition selectors.
- Anatomically reviewed model-label configuration.
- Automatic world-space split of raw femoral-cartilage label 2 into medial and
  lateral compartments without deleting cartilage voxels.
- Cartilage-only T2, FA, and MD/ADC extraction metadata and raw voxel tables.
- Runtime installation validation and public-release checks.
- Automated versioned GHCR image publishing with build provenance.

### Changed

- Preserved the original DWI preprocessing and tensor-derived FA/ADC/AD/RD
  calculations.
- Retained `*_ADC.nii.gz` as the original MRtrix filename for the mean
  diffusivity map used in quantitative analysis.
- Applied extraction limits of `0 < T2 <= 150`, `0 < FA <= 1`, and
  `0 < MD/ADC <= 0.01` by default.
- Pinned the MRtrix3 3.0.8 base-image digest and Python environment versions.
- Separated model checkpoints from both Git history and the public image.

### Removed

- Tractography from the subject pipeline and public release.
- The fixed subject-specific x=128 femoral-cartilage split.
- Bone labels 1 and 3 from all quantitative masks.

### Validation

- The final five-stage configuration completed operationally on 31 internal
  subjects with all expected quantitative outputs and no tractography output.
- This operational result is not an external accuracy or clinical validation.
