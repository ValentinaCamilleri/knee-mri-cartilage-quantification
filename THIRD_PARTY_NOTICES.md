# Third-party software notices

The MIT licence in `LICENSE` applies to the original source code in this
repository. The container includes and invokes third-party software under its
own terms. Users and redistributors are responsible for reviewing those terms.

## MRtrix3 base image

The image is based on the official `mrtrix3/mrtrix3:3.0.8` Linux container,
pinned by digest. MRtrix3 source code is distributed under the Mozilla Public
License 2.0.

- Project: https://www.mrtrix.org/
- Source and licence: https://github.com/MRtrix3/mrtrix3
- Container guidance: https://mrtrix.readthedocs.io/en/latest/installation/using_containers.html

## FSL components

The official MRtrix3 container includes FSL components used by this pipeline,
including TOPUP and eddy. Most FSL is licensed for non-commercial use. The
MRtrix3 container documentation also asks container users who have not
previously registered for FSL to do so.

- Licence: https://fsl.fmrib.ox.ac.uk/fsl/docs/license.html
- Registration: https://fsl.fmrib.ox.ac.uk/fsldownloads_registration

Do not describe the combined container as permitting unrestricted commercial
use merely because this repository's original code is MIT licensed.

## ANTs

ANTs tools from the MRtrix3 base image are used for N4 bias-field correction.
Rigid PD-to-DWI registration is performed by MRtrix3.

- Project and licence: https://github.com/ANTsX/ANTs

## nnU-Net and Python environment

The segmentation environment includes nnU-Net v2 and its dependencies. nnU-Net
is Apache-2.0 licensed; other packages retain their respective licences.

- nnU-Net: https://github.com/MIC-DKFZ/nnUNet
- PyTorch: https://github.com/pytorch/pytorch
- Pinned Python packages: `config/nnunet-requirements.txt`

The trained Dataset501 checkpoint files are separate artifacts and are not
covered automatically by either the repository's MIT licence or nnU-Net's
Apache-2.0 software licence. See `models/MODEL_CARD.md`.
