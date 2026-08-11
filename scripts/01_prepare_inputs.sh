#!/usr/bin/env bash
set -euo pipefail

SUBJECT="${1:?Usage: 01_prepare_inputs.sh sub-XXX}"

DATA_ROOT="${DATA_ROOT:-/data}"
WORK_ROOT="${WORK_ROOT:-/work}"
PYTHON_BIN="${PYTHON_BIN:-/opt/conda/envs/nnunet/bin/python}"
if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="python3"
fi

SESSION_ID="${SESSION_ID:-ses-1}"

PD_RUN="${PD_RUN:-}"
T2_RUN="${T2_RUN:-}"
DWI_RUN="${DWI_RUN:-}"
EPI_RUN="${EPI_RUN:-$DWI_RUN}"

# Explicit paths allow non-BIDS filenames. Paths are interpreted inside the
# container, so files normally need to be under a mounted directory.
PD_IMAGE_OVERRIDE="${PD_IMAGE:-}"
DWI_IMAGE_OVERRIDE="${DWI_IMAGE:-}"
DWI_BVAL_OVERRIDE="${DWI_BVAL:-}"
DWI_BVEC_OVERRIDE="${DWI_BVEC:-}"
DWI_JSON_OVERRIDE="${DWI_JSON:-}"
REVERSE_EPI_IMAGE_OVERRIDE="${REVERSE_EPI_IMAGE:-}"
REVERSE_EPI_JSON_OVERRIDE="${REVERSE_EPI_JSON:-}"
T2_MAP_OVERRIDE="${T2_MAP:-}"
T2_REFERENCE_IMAGE_OVERRIDE="${T2_REFERENCE_IMAGE:-}"

SESSION_DIR="${DATA_ROOT}/${SUBJECT}/${SESSION_ID}"
INPUT_DIR="${WORK_ROOT}/${SUBJECT}/input"

if [[ ! -d "$SESSION_DIR" && ( -z "$PD_IMAGE_OVERRIDE" || -z "$DWI_IMAGE_OVERRIDE" || -z "$REVERSE_EPI_IMAGE_OVERRIDE" || -z "$T2_MAP_OVERRIDE" ) ]]; then
    echo "ERROR: Session directory not found:"
    echo "  $SESSION_DIR"
    exit 1
fi

mkdir -p "$INPUT_DIR"
rm -f "$INPUT_DIR"/*

# ------------------------------------------------------------
# PD image
# ------------------------------------------------------------
if [[ -n "$PD_IMAGE_OVERRIDE" ]]; then
    PD_FILES=("$PD_IMAGE_OVERRIDE")
elif [[ -n "$PD_RUN" ]]; then
    mapfile -t PD_FILES < <(
        find "${SESSION_DIR}/anat" \
            -maxdepth 1 \
            -type f \
            -name "*${PD_RUN}*_PDw.nii.gz" \
            | sort
    )
else
    mapfile -t PD_FILES < <(
        find "${SESSION_DIR}/anat" \
            -maxdepth 1 \
            -type f \
            -name "*_PDw.nii.gz" \
            | sort
    )
fi

if [[ "${#PD_FILES[@]}" -ne 1 ]]; then
    echo "ERROR: Expected exactly one PD-weighted image file."
    echo
    echo "Session used: $SESSION_ID"
    if [[ -n "$PD_RUN" ]]; then
        echo "Requested PD_RUN: $PD_RUN"
    else
        echo "No PD_RUN was specified."
    fi
    echo
    echo "Available PD-weighted files:"
    find "${SESSION_DIR}/anat" \
        -maxdepth 1 \
        -type f \
        -name "*_PDw.nii.gz" \
        | sort \
        | sed 's/^/  /' || true
    exit 1
fi

PD_IMG="${PD_FILES[0]}"

if [[ ! -f "$PD_IMG" ]]; then
    echo "ERROR: PD image not found: $PD_IMG"
    exit 1
fi

# ------------------------------------------------------------
# DWI image
# ------------------------------------------------------------
if [[ -n "$DWI_IMAGE_OVERRIDE" ]]; then
    DWI_FILES=("$DWI_IMAGE_OVERRIDE")
elif [[ -n "$DWI_RUN" ]]; then
    mapfile -t DWI_FILES < <(
        find "${SESSION_DIR}/dwi" \
            -maxdepth 1 \
            -type f \
            -name "*${DWI_RUN}*_dwi.nii.gz" \
            | sort
    )
else
    mapfile -t DWI_FILES < <(
        find "${SESSION_DIR}/dwi" \
            -maxdepth 1 \
            -type f \
            -name "*_dwi.nii.gz" \
            | sort
    )
fi

if [[ "${#DWI_FILES[@]}" -ne 1 ]]; then
    echo "ERROR: Expected exactly one DWI image file."
    echo
    echo "Session used: $SESSION_ID"
    if [[ -n "$DWI_RUN" ]]; then
        echo "Requested DWI_RUN: $DWI_RUN"
    else
        echo "No DWI_RUN was specified."
    fi
    echo
    echo "Available DWI files:"
    find "${SESSION_DIR}/dwi" \
        -maxdepth 1 \
        -type f \
        -name "*_dwi.nii.gz" \
        | sort \
        | sed 's/^/  /'
    echo
    echo "Rerun with one of:"
    echo "  --env DWI_RUN=run-01"
    echo "  --env DWI_RUN=run-02"
    echo "  --env DWI_RUN=run-03"
    exit 1
fi

DWI_IMG="${DWI_FILES[0]}"
DWI_BASE="${DWI_IMG%.nii.gz}"
DWI_BVAL="${DWI_BVAL_OVERRIDE:-${DWI_BASE}.bval}"
DWI_BVEC="${DWI_BVEC_OVERRIDE:-${DWI_BASE}.bvec}"
DWI_JSON="${DWI_JSON_OVERRIDE:-${DWI_BASE}.json}"

for f in "$DWI_IMG" "$DWI_BVAL" "$DWI_BVEC" "$DWI_JSON"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Missing DWI sidecar:"
        echo "  $f"
        exit 1
    fi
done

# ------------------------------------------------------------
# Reverse EPI / fieldmap image
# ------------------------------------------------------------
if [[ -n "$REVERSE_EPI_IMAGE_OVERRIDE" ]]; then
    EPI_FILES=("$REVERSE_EPI_IMAGE_OVERRIDE")
elif [[ -n "$EPI_RUN" ]]; then
    mapfile -t EPI_FILES < <(
        find "${SESSION_DIR}/fmap" \
            -maxdepth 1 \
            -type f \
            -name "*${EPI_RUN}*_epi.nii.gz" \
            | sort
    )
else
    mapfile -t EPI_FILES < <(
        find "${SESSION_DIR}/fmap" \
            -maxdepth 1 \
            -type f \
            -name "*_epi.nii.gz" \
            | sort
    )
fi

if [[ "${#EPI_FILES[@]}" -ne 1 ]]; then
    echo "ERROR: Expected exactly one reverse-EPI image file."
    echo
    echo "Session used: $SESSION_ID"
    if [[ -n "$EPI_RUN" ]]; then
        echo "Requested EPI_RUN: $EPI_RUN"
    else
        echo "No EPI_RUN was specified."
    fi
    echo
    echo "Available reverse-EPI files:"
    find "${SESSION_DIR}/fmap" \
        -maxdepth 1 \
        -type f \
        -name "*_epi.nii.gz" \
        | sort \
        | sed 's/^/  /'
    echo
    echo "Rerun with one of:"
    echo "  --env EPI_RUN=run-01"
    echo "  --env EPI_RUN=run-02"
    exit 1
fi

EPI_IMG="${EPI_FILES[0]}"
EPI_BASE="${EPI_IMG%.nii.gz}"
EPI_JSON="${REVERSE_EPI_JSON_OVERRIDE:-${EPI_BASE}.json}"

for f in "$EPI_IMG" "$EPI_JSON"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Missing reverse-EPI image or JSON:"
        echo "  $f"
        exit 1
    fi
done

# ------------------------------------------------------------
# T2 map
# ------------------------------------------------------------
if [[ -n "$T2_MAP_OVERRIDE" ]]; then
    T2_FILES=("$T2_MAP_OVERRIDE")
elif [[ -n "$T2_RUN" ]]; then
    mapfile -t T2_FILES < <(
        find "${DATA_ROOT}/derivatives/${SUBJECT}" \
            -type f \
            -name "*${T2_RUN}*_T2map.nii.gz" \
            | sort
    )
else
    mapfile -t T2_FILES < <(
        find "${DATA_ROOT}/derivatives/${SUBJECT}" \
            -type f \
            -name "*_T2map.nii.gz" \
            | sort
    )
fi

if [[ "${#T2_FILES[@]}" -ne 1 ]]; then
    echo "ERROR: Expected exactly one T2 map."
    echo
    if [[ -n "$T2_RUN" ]]; then
        echo "Requested T2_RUN: $T2_RUN"
    else
        echo "No T2_RUN was specified."
    fi
    echo
    echo "Available T2 maps:"
    find "${DATA_ROOT}/derivatives/${SUBJECT}" \
        -type f \
        -name "*_T2map.nii.gz" \
        | sort \
        | sed 's/^/  /'
    exit 1
fi

T2_MAP="${T2_FILES[0]}"

if [[ ! -f "$T2_MAP" ]]; then
    echo "ERROR: T2 map not found: $T2_MAP"
    exit 1
fi

# The first T2-weighted echo is a better registration target than a fitted T2
# map. It is optional; stage 5 falls back to the map when it is unavailable.
T2_REFERENCE_IMAGE="$T2_REFERENCE_IMAGE_OVERRIDE"
if [[ -z "$T2_REFERENCE_IMAGE" && -d "${SESSION_DIR}/anat" ]]; then
    mapfile -t T2_REFERENCE_FILES < <(
        find "${SESSION_DIR}/anat" \
            -maxdepth 1 \
            -type f \
            -name "*_echo-01_T2w.nii.gz" \
            | sort
    )
    if [[ "${#T2_REFERENCE_FILES[@]}" -eq 1 ]]; then
        T2_REFERENCE_IMAGE="${T2_REFERENCE_FILES[0]}"
    fi
fi

if [[ -n "$T2_REFERENCE_IMAGE" && ! -f "$T2_REFERENCE_IMAGE" ]]; then
    echo "ERROR: T2 registration reference not found: $T2_REFERENCE_IMAGE"
    exit 1
fi

# ------------------------------------------------------------
# Create working input links/files
# ------------------------------------------------------------
ln -s "$PD_IMG" "$INPUT_DIR/pd.nii.gz"

ln -s "$DWI_IMG"  "$INPUT_DIR/dwi_AP.nii.gz"
ln -s "$DWI_BVAL" "$INPUT_DIR/dwi_AP.bval"
ln -s "$DWI_BVEC" "$INPUT_DIR/dwi_AP.bvec"
ln -s "$DWI_JSON" "$INPUT_DIR/dwi_AP.json"

ln -s "$EPI_IMG"  "$INPUT_DIR/dwi_reverse.nii.gz"
ln -s "$EPI_JSON" "$INPUT_DIR/dwi_reverse.json"

# The reverse-EPI image is treated as a b0 image for MRtrix import.
NVOL="$(mrinfo "$EPI_IMG" -size | awk '{if (NF >= 4) print $4; else print 1}')"

"$PYTHON_BIN" - "$NVOL" "$INPUT_DIR/dwi_reverse.bval" "$INPUT_DIR/dwi_reverse.bvec" <<'PY'
import sys
n = int(sys.argv[1])
bval_path = sys.argv[2]
bvec_path = sys.argv[3]

with open(bval_path, "w") as f:
    f.write(" ".join(["0"] * n) + "\n")

with open(bvec_path, "w") as f:
    f.write(" ".join(["0"] * n) + "\n")
    f.write(" ".join(["0"] * n) + "\n")
    f.write(" ".join(["0"] * n) + "\n")
PY

ln -s "$T2_MAP" "$INPUT_DIR/t2map.nii.gz"
if [[ -n "$T2_REFERENCE_IMAGE" ]]; then
    ln -s "$T2_REFERENCE_IMAGE" "$INPUT_DIR/t2_reference.nii.gz"
fi

cat > "$INPUT_DIR/inputs.env" <<EOF_ENV
SUBJECT=${SUBJECT}
SESSION_ID=${SESSION_ID}
PD_RUN=${PD_RUN}
T2_RUN=${T2_RUN}
DWI_RUN=${DWI_RUN}
EPI_RUN=${EPI_RUN}
PD_IMG=${PD_IMG}
DWI_IMG=${DWI_IMG}
DWI_BVAL=${DWI_BVAL}
DWI_BVEC=${DWI_BVEC}
DWI_JSON=${DWI_JSON}
EPI_IMG=${EPI_IMG}
EPI_JSON=${EPI_JSON}
T2_MAP=${T2_MAP}
T2_REFERENCE_IMAGE=${T2_REFERENCE_IMAGE}
EOF_ENV

echo "========================================"
echo "Input preparation completed"
echo "========================================"
echo "Subject:             $SUBJECT"
echo "Session:             $SESSION_ID"

if [[ -n "$PD_RUN" ]]; then
    echo "Selected PD run:      $PD_RUN"
fi
if [[ -n "$DWI_RUN" ]]; then
    echo "Selected DWI run:     $DWI_RUN"
fi
if [[ -n "$EPI_RUN" ]]; then
    echo "Selected EPI run:     $EPI_RUN"
fi
if [[ -n "$T2_RUN" ]]; then
    echo "Selected T2 run:      $T2_RUN"
fi

echo "PD image:            $PD_IMG"
echo "DWI image:           $DWI_IMG"
echo "Reverse EPI image:   $EPI_IMG"
echo "T2 map:              $T2_MAP"
if [[ -n "$T2_REFERENCE_IMAGE" ]]; then
    echo "T2 registration ref: $T2_REFERENCE_IMAGE"
fi
echo
echo "Working input folder:"
echo "$INPUT_DIR"
echo
echo "Manifest:"
echo "$INPUT_DIR/inputs.env"
