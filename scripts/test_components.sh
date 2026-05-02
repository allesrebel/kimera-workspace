#!/bin/bash
set -e

# Go to the workspace root
cd "$(dirname "$0")/.."

echo "Testing Kimera components independently..."

# 1. Kimera-RPGO
echo "Building and testing Kimera-RPGO..."
cd src/Kimera-RPGO
mkdir -p build && cd build
cmake ..
make -j$(nproc)
./testRpgo || echo "Kimera-RPGO tests failed"
cd ../../..

# 2. Kimera-VIO
echo "Building and testing Kimera-VIO..."
cd src/Kimera-VIO
mkdir -p build && cd build
cmake ..
make -j$(nproc)
./testKimeraVIO || echo "Kimera-VIO tests failed"
cd ../../..

# 3. Kimera-Semantics (Note: Might require ROS or specific dependencies)
echo "Building and testing Kimera-Semantics..."
if [ -d "src/Kimera-Semantics" ]; then
    cd src/Kimera-Semantics
    # Check if there is a standalone test
    if [ -f "CMakeLists.txt" ]; then
        mkdir -p build && cd build
        cmake .. || echo "Kimera-Semantics standalone build failed (expected if ROS-only)"
        make -j$(nproc) || echo "Kimera-Semantics standalone make failed"
    fi
    cd ../../..
fi

echo "Component testing finished."
