#!/bin/bash
# Build the catkin half of the workspace (voxblox, Kimera-Semantics,
# Kimera-VIO-ROS, kalibr) inside the kimera_ros conda env. The native
# /usr/local install (libkimera_vio.so, libgtsam, etc.) is untouched.
#
# Prerequisite: scripts/setup_ros_env.sh has run and the kimera_ros env is
# the active conda env. We refuse to run otherwise to avoid silent
# system-toolchain mixing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${ROS_DISTRO:-}" ] || [ "${ROS_DISTRO}" != "noetic" ]; then
    echo "ERROR: ROS Noetic env is not active. Run scripts/setup_ros_env.sh first," >&2
    echo "       then activate the kimera_ros env (see that script's output)." >&2
    exit 1
fi

if [ -z "${CONDA_PREFIX:-}" ]; then
    echo "ERROR: CONDA_PREFIX not set; this script must run inside the conda env." >&2
    exit 1
fi

cd "${REPO_ROOT}"

# Auto-set the env var that gates voxblox's glog-linking test executables
# (test_load_esdf, tsdf_to_esdf, voxblox_eval, simulation_eval, visualize_tsdf).
# Those binaries include <glog/logging.h> directly and fail under conda-forge
# glog 0.7. Runtime nodes (tsdf_server, esdf_server, kimera_*_node, etc.)
# are unaffected — they link glog via the library targets.
export KIMERA_WORKSPACE_SKIP_VOXBLOX_TESTS=1

# First-time catkin config. Idempotent (catkin config returns 0 on existing config).
# OpenCV_DIR points at the system 4.5 install (which has the cv::viz module
# that Kimera-VIO uses). Combined with the cv_bridge source build from
# src/vision_opencv (added by setup_workspace.sh), this keeps the OpenCV ABI
# consistent across libkimera_vio.so, libcv_bridge.so, and the
# kimera_vio_ros_node binary.
catkin config \
    --init \
    --extend "${CONDA_PREFIX}" \
    --merge-devel \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF -DGTSAM_WERROR=OFF -DCMAKE_CXX_FLAGS="-Wno-error -Wno-deprecated-copy -Wno-maybe-uninitialized" -Dimage_geometry_DIR="${CONDA_PREFIX}/share/image_geometry/cmake" -Dimage_proc_DIR="${CONDA_PREFIX}/share/image_proc/cmake" -DKIMERA_BUILD_TESTS=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Pangolin=ON -DOpenCV_DIR=/usr/lib/x86_64-linux-gnu/cmake/opencv4 -DGLOG_PREFER_EXPORTED_GLOG_CMAKE_CONFIGURATION=OFF -DGLOG_LIBRARY="${REPO_ROOT}/devel/lib/libglog.so" -DGLOG_INCLUDE_DIR="${REPO_ROOT}/devel/include"

# Ensure newly built shared libraries are findable by tools built in this workspace
export LD_LIBRARY_PATH="${REPO_ROOT}/devel/lib:${LD_LIBRARY_PATH:-}"

# catkin_tools resolves the dep graph across the workspace; build everything.
catkin build -j"$(nproc)"

# Surface the produced node binaries so the user can confirm.
echo
echo "Catkin build complete. Produced ROS nodes:"
find devel/lib -maxdepth 2 -type f -executable | sort | head -40
