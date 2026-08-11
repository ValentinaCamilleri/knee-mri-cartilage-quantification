# Knee MRI Cartilage Segmentation and Quantitative MRI Pipeline

A containerised research pipeline for automated knee cartilage segmentation and quantitative analysis of T2 and diffusion MRI. The workflow combines an nnU-Net v2 cartilage segmentation model with MRtrix3-based diffusion preprocessing, image registration, tensor-derived diffusion metrics, and compartment-level extraction of quantitative MRI measurements.

The software is intended for **research use only**. It is not a medical device and must not be used for clinical diagnosis, treatment selection, or unsupervised clinical reporting. Segmentation, registration, diffusion preprocessing, and quantitative outputs should be independently quality controlled before scientific interpretation.

---

## Current release

- **Container image:** `ghcr.io/valentinacamilleri/knee-mri-cartilage-quantification:1.0.0`
- **Segmentation framework:** nnU-Net v2
- **nnU-Net configuration:** `3d_fullres`
- **Runtime model:** fold 0
- **Dataset identifier:** `Dataset501_KneeCartilage`
- **Trainer:** `nnUNetTrainer`
- **Plans:** `nnUNetPlans`
- **Checkpoint:** `checkpoint_final.pth`

The trained fold-0 checkpoint is packaged directly within the published Docker image. Users pulling the published container therefore do **not** need to download or mount the model separately.

Model checkpoint files are intentionally excluded from the Git repository.

---

## Training-data provenance and attribution

The cartilage segmentation model distributed with this project was developed using data obtained from the **OAI-ZIB dataset**.

OAI-ZIB is a publicly released knee MRI research dataset prepared by the Zuse Institute Berlin (ZIB) using imaging data originating from the **Osteoarthritis Initiative (OAI)**. The OAI-ZIB dataset contains 507 OAI knee MRI examinations with reference segmentations of the femoral and tibial bones and articular cartilage.

The OAI-ZIB dataset is **not an original dataset produced by this project**. Appropriate attribution to the original dataset authors must therefore be retained when this software or the trained segmentation model is used in research publications, presentations, derivative software, or other scientific outputs.

### OAI-ZIB dataset citation

The OAI-ZIB research-data release should be cited as:

> Ambellan, F., Tack, A., Ehlke, M., & Zachow, S. (2019). *Automated Segmentation of Knee Bone and Cartilage combining Statistical Shape Knowledge and Convolutional Neural Networks: Data from the Osteoarthritis Initiative (Supplementary Material)* [Research data]. Zuse Institute Berlin. DOI: `10.12752/4.ATEZ.1.0`.

The associated peer-reviewed publication describing the dataset and segmentation methodology should also be cited where appropriate:

> Ambellan, F., Tack, A., Ehlke, M., & Zachow, S. (2019). Automated segmentation of knee bone and cartilage combining statistical shape knowledge and convolutional neural networks: Data from the Osteoarthritis Initiative. *Medical Image Analysis, 52*, 109–118. DOI: `10.1016/j.media.2018.11.009`.

The OAI-ZIB research-data release is distributed under the **Creative Commons Attribution 4.0 International (CC BY 4.0)** licence. Appropriate attribution to the original authors must therefore be preserved.

### Osteoarthritis Initiative provenance

The MRI data underlying OAI-ZIB originate from the **Osteoarthritis Initiative (OAI)**, a multicentre longitudinal observational study sponsored by the United States National Institutes of Health.

Researchers using OAI-derived data should also comply with the current OAI data-use, acknowledgement, and publication requirements.

This project does **not** claim authorship or ownership of the OAI-ZIB dataset or the underlying OAI imaging data. The trained nnU-Net checkpoint distributed with this project is a derived research artifact developed using those data.

---

## Scope of the pipeline

The current release supports two principal modes of operation:

1. **cartilage segmentation only**; and
2. **full quantitative MRI processing**, including T2 and diffusion-derived measurements.

---

## 1. Cartilage segmentation only

The segmentation stage requires a single structural knee MRI.

Within the container working directory, the image must be available as:

```text
/work/sub-XXX/input/pd.nii.gz
