# Version 1.4.0 release checklist

Do not publish the GitHub release or model weights until every blocking item is
resolved.

## Completed technical preparation

- [x] Final five-stage pipeline completed on 31 internal subjects.
- [x] Expected segmentation, DWI, T2, FA, ADC/MD, AD, RD, CSV, and JSON outputs
      were produced.
- [x] No tractography outputs were produced by the final run.
- [x] Model checkpoints and participant data are ignored by Git.
- [x] Public Docker build excludes model checkpoints from its build context.
- [x] MRtrix3 base image is pinned to the tested 3.0.8 digest.
- [x] Python, PyTorch, nnU-Net, and other Python packages are version-pinned.
- [x] GHCR release workflow uses least-privilege repository permissions and
      SHA-pinned third-party actions.
- [x] Runtime and local release checks are available.

## Blocking model-governance decisions

- [ ] Document the training-data source, cohort, inclusion criteria, annotation
      process, consent/governance basis, and redistribution constraints.
- [ ] Confirm that the training-data terms permit public distribution of the
      trained weights.
- [ ] Select an explicit model-weight licence; the repository MIT licence does
      not automatically cover the checkpoints.
- [ ] Upload the complete five-fold model package to an archival record such as
      Zenodo and obtain a versioned DOI.
- [ ] Verify the uploaded package against `models/checksums.sha256`.
- [ ] Add the model DOI/download URL and licence to `README.md` and
      `models/MODEL_CARD.md`.
- [ ] Remove the "publication pending" language only after the record is live.

## Licensing and scientific review

- [ ] Confirm the intended non-commercial/research distribution is compatible
      with the FSL terms bundled in the MRtrix3 base image.
- [ ] Review the model card, anatomical label mapping, limitations, and
      research-only disclaimer with the responsible scientific author.
- [ ] Add formal external performance results if available; do not present the
      31-subject operational run as an accuracy validation.
- [ ] Confirm all required software and paper citations.

## Source and container publication

- [x] Run `bash scripts/release_checks.sh` on the prepared tree and resolve every
      error (completed 2026-08-11; rerun after any changes).
- [ ] Perform a clean code-only Docker build and run `--check` with the complete
      model package mounted read-only.
- [ ] Review `git diff main...release/v1.4.0`.
- [ ] Commit the approved release files on `release/v1.4.0`.
- [ ] Push the branch and merge it through a reviewed pull request.
- [ ] Create GitHub release `v1.4.0`; this triggers the GHCR workflow.
- [ ] Confirm the workflow build and provenance attestation succeeded.
- [ ] Change the GHCR package visibility to public.
- [ ] Test an anonymous pull and a clean run using the archived model package.
- [ ] Enable the GitHub repository in Zenodo if a DOI for the source release is
      desired.

## Expected public image

```text
ghcr.io/valentinacamilleri/knee-mri-quantitative-pipeline:1.4.0
```

Do not publish the locally hot-patched `knee-mri-pipeline:1.4` image. The GHCR
image must be built cleanly from the reviewed Git tag.
