#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPOSITORY_ROOT"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

echo "Checking shell syntax"
while IFS= read -r -d '' shell_script; do
    bash -n "$shell_script"
done < <(find scripts -type f -name '*.sh' -print0)

echo "Checking required release files"
required_files=(
    CHANGELOG.md
    CITATION.cff
    Dockerfile
    LICENSE
    README.md
    RELEASE_CHECKLIST.md
    THIRD_PARTY_NOTICES.md
    config/cartilage-labels.json
    models/MODEL_CARD.md
    models/README.md
    models/checksums.sha256
    .github/workflows/publish-container.yml
    .github/workflows/release-checks.yml
)
for required_file in "${required_files[@]}"; do
    [[ -f "$required_file" ]] || fail "Required release file is missing: $required_file"
done

echo "Checking release version consistency"
docker_version="$(sed -n 's/^ARG PIPELINE_VERSION=//p' Dockerfile)"
citation_version="$(sed -n 's/^version: //p' CITATION.cff | tr -d '\"')"
[[ -n "$docker_version" ]] || fail "Dockerfile does not declare PIPELINE_VERSION"
[[ "$docker_version" == "$citation_version" ]] || \
    fail "Dockerfile version $docker_version does not match CITATION.cff version $citation_version"

echo "Checking five-stage runner"
grep -q 'Stage 1/5:' scripts/06_run_subject_pipeline.sh || fail "Subject runner is not labelled as five stages"
grep -q 'Stage 5/5:' scripts/06_run_subject_pipeline.sh || fail "Subject runner has no fifth stage"
if grep -q '08_run_tractography' scripts/06_run_subject_pipeline.sh; then
    fail "Subject runner still calls tractography"
fi
[[ ! -e scripts/08_run_tractography.sh ]] || fail "Tractography script is still present"

echo "Checking structured metadata"
python3 - <<'PY'
import json
from pathlib import Path

config = json.loads(Path("config/cartilage-labels.json").read_text())
expected = {"0", "1", "2", "3", "4", "5"}
raw_labels = set(config["raw_model_labels"])
if raw_labels != expected:
    raise SystemExit(
        f"ERROR: cartilage-labels.json raw labels are {sorted(raw_labels)}, expected {sorted(expected)}"
    )
PY

echo "Checking Git content boundaries"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    forbidden_pattern='(^|/)(Dockerfile\.runtime-update|08_run_tractography\.sh)$|(^|/)(checkpoint[^/]*\.pth|.*\.(nii|nii\.gz|mif|tck|trk|mgz|bval|bvec|sif|img|tar|tar\.gz))$'
    forbidden_files="$(git ls-files | grep -E "$forbidden_pattern" || true)"
    [[ -z "$forbidden_files" ]] || fail "Forbidden data, model, or local runtime files are tracked:\n$forbidden_files"

    while IFS= read -r tracked_file; do
        [[ -n "$tracked_file" ]] || continue
        [[ -f "$tracked_file" ]] || continue
        size_bytes="$(wc -c < "$tracked_file")"
        if (( size_bytes >= 100000000 )); then
            fail "Tracked file is at least 100 MB: $tracked_file ($size_bytes bytes)"
        fi
    done < <(git ls-files)

    git diff --check
    git diff --cached --check
fi

echo "Release source checks passed."
