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

# Build GTSAM, OpenGV, and DBoW2 from source in parallel.
# These three libraries are independent, so we kick each one off in the
# background and wait at the end. `make install` writes to system paths,
# which is safe under root or sudo as a single concurrent writer per build.
LOG_DIR="/tmp/kimera_build_logs"
mkdir -p "$LOG_DIR"

build_gtsam() {
    cd /tmp
    if [ ! -d "gtsam" ]; then
        git clone --depth 1 --branch 4.1.1 https://github.com/borglab/gtsam.git
    fi
    cd gtsam
    mkdir -p build && cd build
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DGTSAM_BUILD_WITH_TBB=ON \
        -DGTSAM_BUILD_TESTS=OFF \
        -DGTSAM_BUILD_EXAMPLES=OFF \
        -DGTSAM_POSE3_EXPMAP=ON \
        -DGTSAM_ROT3_EXPMAP=ON
    make -j"$(nproc)"
    $SUDO make install
}

build_opengv() {
    cd /tmp
    if [ ! -d "opengv" ]; then
        git clone --depth 1 https://github.com/laurentkneip/opengv.git
    fi
    cd opengv
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)"
    $SUDO make install
}

build_dbow2() {
    cd /tmp
    if [ ! -d "DBoW2" ]; then
        git clone --depth 1 https://github.com/dorian3d/DBoW2.git
    fi
    cd DBoW2
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"$(nproc)"
    $SUDO make install
}

echo "Building GTSAM, OpenGV, DBoW2 in parallel (logs in $LOG_DIR)..."
( build_gtsam  > "$LOG_DIR/gtsam.log"  2>&1 && echo OK > "$LOG_DIR/gtsam.status"  || echo "FAILED rc=$?" > "$LOG_DIR/gtsam.status"  ) &
PID_GTSAM=$!
( build_opengv > "$LOG_DIR/opengv.log" 2>&1 && echo OK > "$LOG_DIR/opengv.status" || echo "FAILED rc=$?" > "$LOG_DIR/opengv.status" ) &
PID_OPENGV=$!
( build_dbow2  > "$LOG_DIR/dbow2.log"  2>&1 && echo OK > "$LOG_DIR/dbow2.status"  || echo "FAILED rc=$?" > "$LOG_DIR/dbow2.status"  ) &
PID_DBOW2=$!

wait $PID_GTSAM $PID_OPENGV $PID_DBOW2

$SUDO ldconfig

fail=0
for d in gtsam opengv dbow2; do
    status=$(cat "$LOG_DIR/$d.status" 2>/dev/null || echo "MISSING")
    echo "  $d: $status"
    [ "$status" = "OK" ] || fail=1
done

if [ $fail -ne 0 ]; then
    echo "One or more dependency builds failed. See $LOG_DIR/*.log for details."
    exit 1
fi

echo "System dependencies installed successfully."
