# nnU-Net model distribution

Model weights are deliberately excluded from Git and the public container. A
single checkpoint is approximately 247 MB, and the five-fold package requires
its own provenance record, reuse licence, version, and checksum manifest.

Model publication is pending those approvals. See `MODEL_CARD.md`,
`checksums.sha256`, and `../RELEASE_CHECKLIST.md`. Do not redistribute the local
checkpoints merely because the pipeline source code is MIT licensed.

At runtime, mount an nnU-Net results directory at `/models`:

```text
-v /path/to/nnUNet_results:/models:ro
```

The expected model folder is:

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

Select every available checkpoint with `NNUNET_FOLDS=auto`, or use an explicit
list such as `NNUNET_FOLDS="0 1 2 3 4"`.

The Docker build context excludes checkpoint files even if local weights are
present under this directory. This prevents accidental publication in GHCR.
