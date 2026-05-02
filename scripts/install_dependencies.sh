#!/bin/bash
set -e

# Define sudo command if available and needed
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "Warning: Not root and sudo not found. Installation of system packages may fail."
  fi
fi

echo "Installing system dependencies for Kimera..."

# Update and install basic tools
$SUDO apt-get update
$SUDO apt-get install -y \
    cmake \
    build-essential \
    pkg-config \
    autoconf \
    libboost-all-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libvtk9-dev \
    libgtk-3-dev \
    libatlas-base-dev \
    gfortran \
    libparmetis-dev \
    libtbb-dev \
    libopencv-dev \
    libgoogle-glog-dev \
    libgflags-dev \
    libpcl-dev \
    protobuf-compiler \
    python3-dev \
    python3-pip \
    unzip \
    wget \
    curl

# Install GTSAM from source (Recommended for Kimera)
echo "Installing GTSAM..."
cd /tmp
if [ ! -d "gtsam" ]; then
    git clone https://github.com/borglab/gtsam.git
fi
cd gtsam
git checkout 4.1.1
mkdir -p build
cd build
cmake .. \
    -DGTSAM_BUILD_WITH_TBB=ON \
    -DGTSAM_BUILD_TESTS=OFF \
    -DGTSAM_BUILD_EXAMPLES=OFF \
    -DGTSAM_POSE3_EXPMAP=ON \
    -DGTSAM_ROT3_EXPMAP=ON
make -j$(nproc)
$SUDO make install
cd ../..
rm -rf gtsam

# Install OpenGV
echo "Installing OpenGV..."
cd /tmp
if [ ! -d "opengv" ]; then
    git clone https://github.com/laurentkneip/opengv.git
fi
cd opengv
mkdir -p build
cd build
cmake ..
make -j$(nproc)
$SUDO make install
cd ../..
rm -rf opengv

# Install DBoW2
echo "Installing DBoW2..."
cd /tmp
if [ ! -d "DBoW2" ]; then
    git clone https://github.com/dorian3d/DBoW2.git
fi
cd DBoW2
mkdir -p build
cd build
cmake ..
make -j$(nproc)
$SUDO make install
cd ../..
rm -rf DBoW2

echo "System dependencies installed successfully."
