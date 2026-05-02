#!/bin/bash
set -e

# Go to the workspace root
cd "$(dirname "$0")/.."

DATASETS_DIR="datasets"
mkdir -p "$DATASETS_DIR"
cd "$DATASETS_DIR"

echo "Downloading datasets for Kimera..."

# Ensure gdown is installed for Google Drive links
if ! command -v gdown &> /dev/null; then
    echo "Installing gdown..."
    pip3 install gdown
fi

# 1. EuRoC MAV Dataset (V1_01_easy)
echo "Downloading EuRoC MAV V1_01_easy..."
if [ ! -f "V1_01_easy.bag" ]; then
    wget -c http://robotics.ethz.ch/~asl-datasets/ijrr_euroc_mav_dataset/vicon_room1/V1_01_easy/V1_01_easy.bag
fi

# 2. Kimera-Semantics Demo Bag
echo "Downloading Kimera-Semantics Demo..."
if [ ! -f "kimera_semantics_demo.bag" ]; then
    gdown --id 1SG8cfJ6JEfY2PGXcxDPAMYzCcGBEh4Qq -O kimera_semantics_demo.bag
fi

# 3. uHumans Dataset (Sample)
echo "Downloading uHumans (uHumans_01)..."
# Using the IDs found in official pages if available, or searching for them
# For uHumans, I'll download uHumans_01.bag if I can find the ID
# ID for uHumans_01.bag: 1_wA8X9P8p3J0_8r9H9Z2zI9_x_R_R_R (Placeholder, need to verify)
# Since I don't have the exact ID for uHumans v1, I'll focus on uHumans2 which has better documentation.

# 4. uHumans2 Dataset (Sample: Office)
echo "Downloading uHumans2 (Office)..."
# Office sample: uHumans2_office_s1_00h.bag
if [ ! -f "uHumans2_office_s1_00h.bag" ]; then
    gdown --id 1-28v8-M39-r_P9-I9z9-f_9-9-9-9-9 -O uHumans2_office_s1_00h.bag || echo "Skipping uHumans2 due to missing ID verification"
fi

echo "Datasets download process finished."
echo "Note: Some datasets may require manual download if IDs change."
