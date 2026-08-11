#!/usr/bin/env bash
set -euo pipefail

OUTPUT_ROOT="${OUTPUT_ROOT:-/output}"
SAVE_RAW_VALUES="${SAVE_RAW_VALUES:-1}"
T2_MAX="${T2_MAX:-150}"
MD_MAX="${MD_MAX:-0.01}"

PYTHON_BIN="${PYTHON_BIN:-/opt/conda/envs/nnunet/bin/python}"

if [[ ! -x "$PYTHON_BIN" ]]; then
    PYTHON_BIN="python3"
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 sub-XXX"
    exit 1
fi

SUBJECT="$1"
SUBJECT_OUTPUT="${OUTPUT_ROOT}/${SUBJECT}"

# Quantitative masks are derived directly from the original nnU-Net output.
# Only cartilage labels 2, 4, and 5 are included; bone labels 1 and 3 are
# excluded. Label 2 is split into medial and lateral femoral cartilage before
# this original-space mask is resampled independently to each metric grid.
SEGMENTATION="${SUBJECT_OUTPUT}/segmentation/${SUBJECT}_cartilage.nii.gz"

T2_MAP="${SUBJECT_OUTPUT}/t2/${SUBJECT}_T2map.nii.gz"
FA_MAP="${SUBJECT_OUTPUT}/diffusion_metrics/${SUBJECT}_FA.nii.gz"
ADC_MAP="${SUBJECT_OUTPUT}/diffusion_metrics/${SUBJECT}_ADC.nii.gz"

ANALYSIS_OUTPUT="${SUBJECT_OUTPUT}/quantitative_analysis"
SUMMARY_CSV="${ANALYSIS_OUTPUT}/${SUBJECT}_segment_statistics.csv"
RAW_VALUES_CSV_GZ="${ANALYSIS_OUTPUT}/${SUBJECT}_segment_voxel_values.csv.gz"
METADATA_JSON="${ANALYSIS_OUTPUT}/${SUBJECT}_extraction_metadata.json"

for required_file in \
    "$SEGMENTATION" \
    "$T2_MAP" \
    "$FA_MAP" \
    "$ADC_MAP"
do
    if [[ ! -f "$required_file" ]]; then
        echo "ERROR: Required original segmentation or metric not found:"
        echo "$required_file"
        exit 1
    fi
done

mkdir -p "$ANALYSIS_OUTPUT"

echo "========================================"
echo "Extracting segment-level values"
echo "========================================"
echo "Subject:              $SUBJECT"
echo "Source segmentation:  $SEGMENTATION"
echo "Included raw labels:  2, 4, 5"
echo "Excluded bone labels: 1, 3"
echo "Femoral split:        automatic world-space split"
echo "T2 valid range:       0 < T2 <= $T2_MAX"
echo "FA valid range:       0 < FA <= 1"
echo "MD valid range:       0 < MD <= $MD_MAX mm^2/s"
echo "Save raw values:      $SAVE_RAW_VALUES"
echo

"$PYTHON_BIN" - \
    "$SUBJECT" \
    "$SEGMENTATION" \
    "$T2_MAP" \
    "$FA_MAP" \
    "$ADC_MAP" \
    "$SUMMARY_CSV" \
    "$RAW_VALUES_CSV_GZ" \
    "$METADATA_JSON" \
    "$SAVE_RAW_VALUES" \
    "$T2_MAX" \
    "$MD_MAX" <<'PY'
import csv
import gzip
import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to


(
    subject,
    segmentation_path,
    t2_path,
    fa_path,
    adc_path,
    summary_csv,
    raw_values_csv_gz,
    metadata_json,
    save_raw_values,
    t2_max,
    md_max,
) = sys.argv[1:]

save_raw_values = int(save_raw_values)
t2_max = float(t2_max)
md_max = float(md_max)

segmentation_path = Path(segmentation_path)
summary_csv = Path(summary_csv)
raw_values_csv_gz = Path(raw_values_csv_gz)
metadata_json = Path(metadata_json)

metrics = [
    {
        "space": "T2",
        "metric": "T2",
        "units": "native_T2_map_units",
        "path": Path(t2_path),
        "minimum": 0.0,
        "maximum": t2_max,
    },
    {
        "space": "DWI",
        "metric": "FA",
        "units": "dimensionless",
        "path": Path(fa_path),
        "minimum": 0.0,
        "maximum": 1.0,
    },
    {
        "space": "DWI",
        "metric": "MD_ADC",
        "units": "mm^2/s",
        "path": Path(adc_path),
        "minimum": 0.0,
        "maximum": md_max,
    },
]

# Retain the original quantitative label IDs. Anatomical review established
# raw label 4 as medial tibial cartilage and raw label 5 as lateral tibial
# cartilage.
label_names = {
    201: "medial_femoral_cartilage",
    202: "lateral_femoral_cartilage",
    4: "medial_tibial_cartilage",
    5: "lateral_tibial_cartilage",
}

excluded_labels = [1, 3]

seg_img_original = nib.load(str(segmentation_path))
seg_original = np.rint(np.asanyarray(seg_img_original.dataobj)).astype(np.int16)
seg_original = np.squeeze(seg_original)

if seg_original.ndim != 3:
    raise RuntimeError(
        f"Original segmentation must be 3-D after squeezing; received {seg_original.shape}"
    )

unique_labels, unique_counts = np.unique(seg_original, return_counts=True)
raw_label_counts = {
    int(label): int(count) for label, count in zip(unique_labels, unique_counts)
}
unexpected_labels = sorted(set(raw_label_counts) - {0, 1, 2, 3, 4, 5})
if unexpected_labels:
    raise RuntimeError(f"Unexpected raw nnU-Net labels: {unexpected_labels}")

missing_cartilage = [
    label for label in (2, 4, 5) if raw_label_counts.get(label, 0) == 0
]
if missing_cartilage:
    raise RuntimeError(f"Required cartilage labels are empty: {missing_cartilage}")


def world_centroid(mask, affine):
    coordinates = np.argwhere(mask)
    if coordinates.size == 0:
        raise RuntimeError("Cannot calculate a centroid for an empty cartilage label")
    return nib.affines.apply_affine(affine, coordinates).mean(axis=0)


# Automatically split femoral cartilage in the original PD space. The plane is
# halfway between the medial (raw 4) and lateral (raw 5) tibial cartilage
# centroids, with its normal running from lateral to medial. No predicted
# cartilage voxels are deleted or cleaned.
medial_tibial_centroid = world_centroid(seg_original == 4, seg_img_original.affine)
lateral_tibial_centroid = world_centroid(seg_original == 5, seg_img_original.affine)
medial_vector = medial_tibial_centroid - lateral_tibial_centroid
centroid_distance = float(np.linalg.norm(medial_vector))
if centroid_distance <= 1.0:
    raise RuntimeError(
        f"Tibial cartilage centroids are only {centroid_distance:.3f} mm apart"
    )

split_midpoint = (medial_tibial_centroid + lateral_tibial_centroid) / 2.0
femoral_coordinates = np.argwhere(seg_original == 2)
femoral_world = nib.affines.apply_affine(
    seg_img_original.affine, femoral_coordinates
)
medial_femoral_side = (
    np.einsum("ij,j->i", femoral_world - split_midpoint, medial_vector) >= 0
)

derived_seg = np.zeros_like(seg_original, dtype=np.int16)
derived_seg[seg_original == 4] = 4
derived_seg[seg_original == 5] = 5
derived_seg[tuple(femoral_coordinates[medial_femoral_side].T)] = 201
derived_seg[tuple(femoral_coordinates[~medial_femoral_side].T)] = 202

derived_label_counts = {
    label: int(np.count_nonzero(derived_seg == label)) for label in label_names
}
if sum(derived_label_counts.values()) != sum(
    raw_label_counts.get(label, 0) for label in (2, 4, 5)
):
    raise RuntimeError("Cartilage voxel count changed while deriving analysis labels")

derived_seg_img = nib.Nifti1Image(
    derived_seg,
    seg_img_original.affine,
    seg_img_original.header,
)

summary_rows = []
raw_rows = []

metadata = {
    "subject": subject,
    "segmentation": str(segmentation_path),
    "included_raw_cartilage_labels": [2, 4, 5],
    "excluded_bone_labels": excluded_labels,
    "raw_label_counts": raw_label_counts,
    "derived_labels": label_names,
    "derived_label_counts": derived_label_counts,
    "femoral_split": {
        "source_label": 2,
        "method": "world-space plane midway between raw labels 4 and 5",
        "medial_tibial_centroid_mm": medial_tibial_centroid.tolist(),
        "lateral_tibial_centroid_mm": lateral_tibial_centroid.tolist(),
        "centroid_distance_mm": centroid_distance,
        "cartilage_voxels_removed": 0,
    },
    "original_segmentation_shape": list(seg_original.shape),
    "metrics": [],
}


def voxel_volume_mm3(image):
    return float(np.prod(image.header.get_zooms()[:3]))


def align_segmentation_to_metric(segmentation_image, metric_image, metric_name):
    segmentation_data = np.asanyarray(segmentation_image.dataobj)
    target = (metric_image.shape[:3], metric_image.affine)

    if (
        segmentation_data.shape != metric_image.shape[:3]
        or not np.allclose(segmentation_image.affine, metric_image.affine)
    ):
        print(
            f"  Aligning derived original-space segmentation to {metric_name} grid: "
            f"{segmentation_data.shape} -> {metric_image.shape[:3]}"
        )
        aligned = resample_from_to(segmentation_image, target, order=0)
        return np.rint(np.asanyarray(aligned.dataobj)).astype(np.int16)

    return np.rint(segmentation_data).astype(np.int16)


def valid_values(values, minimum, maximum):
    values = values.astype(float)
    valid = np.isfinite(values) & (values > minimum) & (values <= maximum)
    return values[valid], int(np.size(values) - np.count_nonzero(valid))


def describe_values(values):
    return {
        "mean": float(np.mean(values)),
        "standard_deviation": float(np.std(values, ddof=1)) if values.size > 1 else 0.0,
        "median": float(np.median(values)),
        "quartile_25": float(np.percentile(values, 25)),
        "quartile_75": float(np.percentile(values, 75)),
        "minimum": float(np.min(values)),
        "maximum": float(np.max(values)),
    }


for metric_info in metrics:
    metric_img = nib.load(str(metric_info["path"]))
    metric_data = np.squeeze(np.asanyarray(metric_img.dataobj))
    if metric_data.ndim != 3:
        raise RuntimeError(
            f"{metric_info['metric']} must be 3-D after squeezing; received {metric_data.shape}"
        )

    seg_metric = align_segmentation_to_metric(
        derived_seg_img,
        metric_img,
        metric_info["metric"],
    )

    if metric_data.shape != seg_metric.shape:
        raise RuntimeError(
            f"Metric and segmentation shapes do not match for {metric_info['metric']}: "
            f"{metric_data.shape} versus {seg_metric.shape}"
        )

    voxvol = voxel_volume_mm3(metric_img)
    zooms = tuple(float(value) for value in metric_img.header.get_zooms()[:3])

    print(
        f"{metric_info['metric']}: shape={metric_data.shape}, "
        f"voxel size={zooms}, valid range=({metric_info['minimum']}, "
        f"{metric_info['maximum']}]"
    )

    metric_meta = {
        "metric": metric_info["metric"],
        "space": metric_info["space"],
        "path": str(metric_info["path"]),
        "shape": list(metric_data.shape),
        "voxel_size": list(zooms),
        "voxel_volume_mm3": voxvol,
        "valid_range": {
            "greater_than": metric_info["minimum"],
            "less_than_or_equal": metric_info["maximum"],
        },
        "regions": [],
    }

    for label_id, label_name in label_names.items():
        region_mask = seg_metric == label_id
        label_voxel_count = int(np.count_nonzero(region_mask))

        if label_voxel_count == 0:
            print(f"  Label {label_id}: {label_name}, 0 voxels, skipped")
            continue

        values_all = metric_data[region_mask]
        values, excluded_voxel_count = valid_values(
            values_all,
            metric_info["minimum"],
            metric_info["maximum"],
        )
        valid_voxel_count = int(values.size)

        print(
            f"  Label {label_id}: {label_name}, "
            f"{valid_voxel_count}/{label_voxel_count} valid voxels"
        )

        if valid_voxel_count == 0:
            continue

        row = {
            "subject": subject,
            "space": metric_info["space"],
            "metric": metric_info["metric"],
            "units": metric_info["units"],
            "label_id": label_id,
            "label_name": label_name,
            "label_voxel_count": label_voxel_count,
            "valid_voxel_count": valid_voxel_count,
            "excluded_voxel_count": excluded_voxel_count,
            "voxel_volume_mm3": voxvol,
            "segment_volume_mm3": label_voxel_count * voxvol,
            "valid_volume_mm3": valid_voxel_count * voxvol,
            **describe_values(values),
        }
        summary_rows.append(row)

        metric_meta["regions"].append(
            {
                "label_id": label_id,
                "label_name": label_name,
                "label_voxel_count": label_voxel_count,
                "valid_voxel_count": valid_voxel_count,
                "excluded_voxel_count": excluded_voxel_count,
            }
        )

        if save_raw_values:
            for value in values:
                raw_rows.append(
                    {
                        "subject": subject,
                        "space": metric_info["space"],
                        "metric": metric_info["metric"],
                        "label_id": label_id,
                        "label_name": label_name,
                        "value": float(value),
                    }
                )

    metadata["metrics"].append(metric_meta)

summary_fields = [
    "subject",
    "space",
    "metric",
    "units",
    "label_id",
    "label_name",
    "label_voxel_count",
    "valid_voxel_count",
    "excluded_voxel_count",
    "voxel_volume_mm3",
    "segment_volume_mm3",
    "valid_volume_mm3",
    "mean",
    "standard_deviation",
    "median",
    "quartile_25",
    "quartile_75",
    "minimum",
    "maximum",
]

with open(summary_csv, "w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=summary_fields)
    writer.writeheader()
    writer.writerows(summary_rows)

if save_raw_values:
    raw_fields = [
        "subject",
        "space",
        "metric",
        "label_id",
        "label_name",
        "value",
    ]
    with gzip.open(raw_values_csv_gz, "wt", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=raw_fields)
        writer.writeheader()
        writer.writerows(raw_rows)

with open(metadata_json, "w") as handle:
    json.dump(metadata, handle, indent=2)

print()
print(f"Summary written to: {summary_csv}")
if save_raw_values:
    print(f"Raw values written to: {raw_values_csv_gz}")
print(f"Metadata written to: {metadata_json}")
PY

echo
echo "Segment-level extraction completed successfully."
echo
echo "Outputs:"
echo "$SUMMARY_CSV"
if [[ "$SAVE_RAW_VALUES" == "1" ]]; then
    echo "$RAW_VALUES_CSV_GZ"
fi
echo "$METADATA_JSON"
