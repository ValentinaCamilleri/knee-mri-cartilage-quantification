FROM mrtrix3/mrtrix3:3.0.8@sha256:a06f1463923d1bb748c5bba09ca1daaf2266802a84e161ba4b28238396afe82a

ARG PIPELINE_VERSION=1.4.0
ARG BUILD_DATE=""
ARG VCS_REF=""

LABEL org.opencontainers.image.title="Knee MRI Quantitative Processing Pipeline" \
      org.opencontainers.image.description="Research pipeline for knee cartilage segmentation and T2/FA/MD extraction" \
      org.opencontainers.image.version="${PIPELINE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/ValentinaCamilleri/knee-mri-quantitative-pipeline" \
      org.opencontainers.image.documentation="https://github.com/ValentinaCamilleri/knee-mri-quantitative-pipeline#readme" \
      org.opencontainers.image.licenses="MIT"

USER root

# Install only the system tools required to install Miniforge.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        bzip2 && \
    rm -rf /var/lib/apt/lists/*

# Install a pinned Miniforge release.
ARG MINIFORGE_VERSION=26.3.2-3
ARG MINIFORGE_SHA256=848194851a98903134187fbb4ab50efe87b003e0c0f808f97644b7524a62bf2c

RUN wget --quiet \
        "https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/Miniforge3-${MINIFORGE_VERSION}-Linux-x86_64.sh" \
        -O /tmp/miniforge.sh && \
    echo "${MINIFORGE_SHA256}  /tmp/miniforge.sh" | sha256sum -c - && \
    bash /tmp/miniforge.sh -b -p /opt/conda && \
    rm /tmp/miniforge.sh

# Create a Python environment matching the working host environment.
RUN /opt/conda/bin/mamba create -y \
        -n nnunet \
        python=3.9.23 \
        pip && \
    /opt/conda/bin/mamba clean --all --yes

# Copy the locked non-PyTorch dependencies first for Docker layer caching.
COPY config/nnunet-requirements.txt /tmp/nnunet-requirements.txt

# Install the exact PyTorch family used by the working environment.
ARG PIP_VERSION=26.0.1
RUN /opt/conda/envs/nnunet/bin/python -m pip install \
        --no-cache-dir \
        "pip==${PIP_VERSION}" && \
    /opt/conda/envs/nnunet/bin/python -m pip install \
        --no-cache-dir \
        torch==2.8.0 \
        torchvision==0.23.0 \
        torchaudio==2.8.0 \
        --index-url https://download.pytorch.org/whl/cu128

# Install the remaining locked nnU-Net environment.
RUN /opt/conda/envs/nnunet/bin/python -m pip install \
        --no-cache-dir \
        -r /tmp/nnunet-requirements.txt && \
    rm /tmp/nnunet-requirements.txt

ENV nnUNet_results=/models
ENV nnUNet_raw=/nnunet/raw
ENV nnUNet_preprocessed=/nnunet/preprocessed
ENV PATH=/opt/conda/envs/nnunet/bin:${PATH}
ENV MPLCONFIGDIR=/tmp/matplotlib

RUN mkdir -p \
        /data \
        /work \
        /output \
        /models \
        /nnunet/raw \
        /nnunet/preprocessed \
        /pipeline/scripts \
        /pipeline/config \
        /licenses \
        /tmp/matplotlib && \
    chmod 1777 /tmp/matplotlib

# Keep runtime-generated MRtrix helper files out of the read-only pipeline
# source directory when the container runs as a non-root host user.
WORKDIR /tmp

COPY scripts/ /pipeline/scripts/
COPY config/ /pipeline/config/

# Package the trained nnU-Net fold-0 model into the image
COPY models/runtime/ /models/
COPY LICENSE /licenses/pipeline-LICENSE
COPY THIRD_PARTY_NOTICES.md /licenses/THIRD_PARTY_NOTICES.md

RUN test -f /models/Dataset501_KneeCartilage/nnUNetTrainer__nnUNetPlans__3d_fullres/fold_0/checkpoint_final.pth && \
    test -f /models/Dataset501_KneeCartilage/nnUNetTrainer__nnUNetPlans__3d_fullres/dataset.json && \
    test -f /models/Dataset501_KneeCartilage/nnUNetTrainer__nnUNetPlans__3d_fullres/plans.json && \
    chmod +x /pipeline/scripts/*.sh && \
    /opt/conda/envs/nnunet/bin/python -c \
      "import nibabel, numpy, scipy, torch, nnunetv2; print('PyTorch:', torch.__version__); print('nnU-Net imported successfully')"

ENTRYPOINT ["/pipeline/scripts/run_pipeline.sh"]
