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

# First-time catkin config. Idempotent (catkin config returns 0 on existing config).
catkin config \
    --init \
    --extend "${CONDA_PREFIX}" \
    --merge-devel \
    --cmake-args -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -Dimage_geometry_DIR="${CONDA_PREFIX}/share/image_geometry/cmake" -Dimage_proc_DIR="${CONDA_PREFIX}/share/image_proc/cmake" -DKIMERA_BUILD_TESTS=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Pangolin=ON -DOpenCV_DIR=/usr/lib/x86_64-linux-gnu/cmake/opencv4

# catkin_tools resolves the dep graph across the workspace; build everything.
catkin build -j"$(nproc)"

# Surface the produced node binaries so the user can confirm.
echo
echo "Catkin build complete. Produced ROS nodes:"
find devel/lib -maxdepth 2 -type f -executable | sort | head -40
