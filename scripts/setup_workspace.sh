#!/bin/bash
set -e

# Go to the workspace root
cd "$(dirname "$0")/.."

echo "Initializing Kimera workspace..."

# Initialize git if not already
if [ ! -d ".git" ]; then
    git init
fi

# Add submodules
echo "Adding Kimera submodules..."

function add_submodule() {
    local url=$1
    local path=$2
    if [ ! -d "$path" ]; then
        git submodule add "$url" "$path"
    else
        echo "Submodule $path already exists, skipping..."
    fi
}

add_submodule https://github.com/MIT-SPARK/Kimera-VIO.git src/Kimera-VIO
add_submodule https://github.com/MIT-SPARK/Kimera-Semantics.git src/Kimera-Semantics
add_submodule https://github.com/MIT-SPARK/Kimera-RPGO.git src/Kimera-RPGO
add_submodule https://github.com/ethz-asl/voxblox.git src/voxblox
# kalibr provides kalibr_bagcreater, used by scripts/download_datasets.sh
# to convert the EuRoC ASL-format zips into ROS bags.
add_submodule https://github.com/ethz-asl/kalibr.git src/kalibr
# Kimera-VIO-ROS bridges native libkimera_vio.so to ROS topics so the
# trajectory can drive voxblox / Kimera-Semantics in the same rosmaster.
add_submodule https://github.com/MIT-SPARK/Kimera-VIO-ROS.git src/Kimera-VIO-ROS

# Initialize and update submodules recursively
echo "Updating submodules..."
git submodule update --init --recursive

# Fetch the ETHZ-ASL / MIT-SPARK helper catkin packages enumerated in the
# upstream rosinstall files (catkin_simple, eigen_catkin, glog_catkin,
# gflags_catkin, minkindr, minkindr_ros, mesh_rviz_plugins, pose_graph_tools,
# voxblox_msgs, etc.). They are not promoted to git submodules; they live as
# plain clones under src/<pkg>/ and are listed in .gitignore.
#
# Requires `vcs` (python-vcstool). It ships with the kimera_ros conda env
# (scripts/setup_ros_env.sh). If vcs is not on PATH, we skip with a hint —
# users who only build the native non-ROS Kimera-VIO don't need these.
if command -v vcs >/dev/null 2>&1; then
    echo "Importing ROS helper packages with vcs..."
    vcs import src < src/voxblox/voxblox_https.rosinstall || true
    vcs import src < src/Kimera-Semantics/install/kimera_semantics_https.rosinstall || true
    vcs import src < src/Kimera-VIO-ROS/install/kimera_vio_ros_https.rosinstall || true

    # vision_opencv (cv_bridge + image_geometry) source: catkin builds it
    # against system OpenCV 4.5 so libcv_bridge.so and downstream nodes share
    # the same OpenCV ABI as the natively-built libkimera_vio.so. Conda ships
    # a prebuilt ros-noetic-cv-bridge linked against conda's OpenCV 4.9; mixing
    # the two in one process is what produced the runtime crash we hit on
    # kimera_vio_ros_node. Catkin's develspace shadows the conda binary at
    # build/link time.
    if [ ! -d src/vision_opencv ]; then
        echo "Cloning vision_opencv (source cv_bridge / image_geometry)..."
        git clone --depth 1 --branch noetic \
            https://github.com/ros-perception/vision_opencv.git \
            src/vision_opencv
        # Skip the umbrella metapackages and tests so catkin doesn't trip on
        # duplicate-package-named dirs.
        touch src/vision_opencv/opencv_tests/CATKIN_IGNORE
        touch src/vision_opencv/vision_opencv/CATKIN_IGNORE
    fi
else
    cat <<'EOF'

Note: vcs (python-vcstool) not on PATH; ROS helper packages NOT fetched.
That is fine if you only need the native Kimera-VIO build. To prepare the
ROS half of the workspace, activate the kimera_ros conda env first:
    source scripts/setup_ros_env.sh   # creates the env if missing
    micromamba activate kimera_ros
    ./scripts/setup_workspace.sh      # rerun; vcs imports will succeed
EOF
fi

echo "Kimera workspace initialized successfully."
