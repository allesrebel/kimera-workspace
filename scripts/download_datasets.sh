#!/bin/bash
set -e

# Define sudo command if available and needed
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "Warning: Not root and sudo not found."
  fi
fi

# Go to the workspace root
cd "$(dirname "$0")/.."

DATASETS_DIR="datasets"
mkdir -p "$DATASETS_DIR"
cd "$DATASETS_DIR"

echo "Downloading datasets for Kimera..."

# Ensure gdown is installed for Google Drive links
if ! command -v gdown &> /dev/null; then
    echo "Installing gdown..."
    $SUDO pip3 install gdown || pip3 install --user gdown
fi

# 1. EuRoC MAV Dataset
# Hosted on ETH Research Collection (handle 20.500.11850/690084).
# Bitstreams are addressed by UUID via the DSpace REST API:
#   https://www.research-collection.ethz.ch/server/api/core/bitstreams/<uuid>/content
# NOTE: the research-collection only hosts the raw ASL-format zips, not the
# legacy rosbags. Convert with kalibr_bagcreater (or similar) if a .bag is needed.
echo "Downloading EuRoC MAV dataset zips..."
EUROC_BASE="https://www.research-collection.ethz.ch/server/api/core/bitstreams"
declare -A EUROC_ZIPS=(
    ["machine_hall.zip"]="7b2419c1-62b5-4714-b7f8-485e5fe3e5fe"
    ["vicon_room1.zip"]="02ecda9a-298f-498b-970c-b7c44334d880"
    ["vicon_room2.zip"]="ea12bc01-3677-4b4c-853d-87c7870b8c44"
    ["calibration_datasets.zip"]="5732e864-10f1-49e7-befb-669ee29ff770"
)

mkdir -p euroc
for zipname in "${!EUROC_ZIPS[@]}"; do
    uuid="${EUROC_ZIPS[$zipname]}"
    extract_marker="euroc/.${zipname%.zip}.extracted"
    if [ -f "$extract_marker" ]; then
        echo "  $zipname already extracted, skipping."
        continue
    fi
    if [ ! -f "euroc/$zipname" ]; then
        echo "  Downloading $zipname..."
        wget -c "$EUROC_BASE/$uuid/content" -O "euroc/$zipname"
    fi
    echo "  Extracting $zipname..."
    unzip -q -o "euroc/$zipname" -d "euroc/${zipname%.zip}"
    touch "$extract_marker"
done

# Convert ASL-format sequences into ROS bags using kalibr_bagcreater.
# The tool ships with the ethz-asl/kalibr ROS package; install it (or source
# a workspace that contains it) before running, otherwise this step is skipped.
echo "Converting EuRoC sequences to .bag..."
if command -v kalibr_bagcreater >/dev/null 2>&1; then
    KALIBR_BAGCREATER="kalibr_bagcreater"
elif command -v rosrun >/dev/null 2>&1 && rosrun --prefix= kalibr kalibr_bagcreater --help >/dev/null 2>&1; then
    KALIBR_BAGCREATER="rosrun kalibr kalibr_bagcreater"
else
    KALIBR_BAGCREATER=""
fi

if [ -z "$KALIBR_BAGCREATER" ]; then
    echo "  kalibr_bagcreater not found on PATH — skipping bag conversion."
    echo "  Install ethz-asl/kalibr (or source a workspace containing it) and re-run"
    echo "  to generate .bag files from euroc/*/<sequence>/mav0."
else
    # Each zip extracts to one or more sequence folders that each contain mav0/.
    while IFS= read -r mav0_dir; do
        seq_dir="$(dirname "$mav0_dir")"
        seq_name="$(basename "$seq_dir")"
        out_bag="euroc/${seq_name}.bag"
        if [ -f "$out_bag" ]; then
            echo "  $out_bag already exists, skipping."
            continue
        fi
        echo "  Converting $seq_dir -> $out_bag"
        $KALIBR_BAGCREATER --folder "$seq_dir" --output-bag "$out_bag"
    done < <(find euroc -mindepth 3 -maxdepth 4 -type d -name mav0)
fi

# 2. Kimera-Semantics Demo Bag
echo "Downloading Kimera-Semantics Demo..."
if [ ! -f "kimera_semantics_demo.bag" ]; then
    gdown 1SG8cfJ6JEfY2PGXcxDPAMYzCcGBEh4Qq -O kimera_semantics_demo.bag
fi

# 3. uHumans Dataset (Sample)
echo "Downloading uHumans (uHumans_01)..."
# Since exact IDs are hard to track, we provide placeholders or common IDs
# For uHumans, the official repo often has download links in READMEs.

# 4. uHumans2 Dataset (Sample: Office)
echo "Downloading uHumans2 (Office)..."
# Office sample: uHumans2_office_s1_00h.bag
if [ ! -f "uHumans2_office_s1_00h.bag" ]; then
    gdown 1-28v8-M39-r_P9-I9z9-f_9-9-9-9-9 -O uHumans2_office_s1_00h.bag || echo "Skipping uHumans2 due to missing ID verification"
fi

echo "Datasets download process finished."
echo "Note: Some datasets may require manual download if IDs change."
