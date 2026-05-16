#!/bin/bash
# Set up the RoboStack conda environment for the ROS Noetic / catkin half of
# the Kimera workspace. ROS 1 has no official Ubuntu 22.04 build; RoboStack
# (conda-forge) ships ros-noetic-* packages that work natively on 22.04.
#
# This script is idempotent: rerunning it picks up where the previous run
# left off (micromamba install, env creation, env update).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_NAME="kimera_ros"
ENV_FILE="${REPO_ROOT}/scripts/kimera_ros.env.yaml"
MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-${HOME}/micromamba}"
MICROMAMBA_BIN="${HOME}/.local/bin/micromamba"

# Pre-flight: env (micromamba root) + working tree share /, so size accordingly.
need_gb=6
avail_gb=$(df -BG --output=avail "${HOME}" | tail -1 | tr -dc '0-9')
if [ "${avail_gb}" -lt "${need_gb}" ]; then
    echo "ERROR: need >= ${need_gb}G free in ${HOME}; have ${avail_gb}G." >&2
    exit 1
fi

# 1. Install micromamba if missing.
if [ ! -x "${MICROMAMBA_BIN}" ] && ! command -v micromamba >/dev/null 2>&1; then
    echo "Installing micromamba to ${MICROMAMBA_BIN}..."
    mkdir -p "$(dirname "${MICROMAMBA_BIN}")"
    # Official static binary release.
    arch=$(uname -m)
    case "${arch}" in
        x86_64) plat="linux-64" ;;
        aarch64) plat="linux-aarch64" ;;
        *) echo "Unsupported arch ${arch}" >&2; exit 1 ;;
    esac
    curl -fsSL \
        "https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-${plat}" \
        -o "${MICROMAMBA_BIN}"
    chmod +x "${MICROMAMBA_BIN}"
fi

# 2. Resolve which micromamba to use.
if [ -x "${MICROMAMBA_BIN}" ]; then
    MAMBA="${MICROMAMBA_BIN}"
else
    MAMBA="$(command -v micromamba)"
fi

export MAMBA_ROOT_PREFIX

# 3. Create or update the kimera_ros env from the YAML.
if "${MAMBA}" env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
    echo "Updating env ${ENV_NAME}..."
    "${MAMBA}" install -y -n "${ENV_NAME}" -f "${ENV_FILE}"
else
    echo "Creating env ${ENV_NAME}..."
    "${MAMBA}" create -y -n "${ENV_NAME}" -f "${ENV_FILE}"
fi

# 4. Post-install fixes. The Kimera-VIO-ROS / voxblox_ros catkin chain has a
# few env-side requirements that the upstream micromamba solver can't satisfy
# in a single solve (it crashes with a libsolv assertion on the full constraint
# graph), so we apply them as direct .conda installs via --no-deps. All
# packages here are pinned to the boost-1.82 / pcl-1.13 ABI family.
ENV_PREFIX="${MAMBA_ROOT_PREFIX}/envs/${ENV_NAME}"
PKG_CACHE="/tmp/kimera_ros_pkgs"
mkdir -p "${PKG_CACHE}"

fetch_and_install_conda() {
    # $1 = filename, $2 = url. Installs via micromamba --no-deps if not present.
    local fname="$1" url="$2"
    if [ ! -f "${PKG_CACHE}/${fname}" ]; then
        echo "Fetching ${fname}..."
        curl -fsSL -o "${PKG_CACHE}/${fname}" "${url}"
    fi
    "${MAMBA}" install -y -n "${ENV_NAME}" --no-deps "${PKG_CACHE}/${fname}" \
        > /dev/null 2>&1 || true
}

echo "Installing pinned-ABI packages directly from .conda artifacts..."
RB="https://conda.anaconda.org/robostack-staging/linux-64"
CF="https://conda.anaconda.org/conda-forge/linux-64"

# boost 1.82 (both runtime and cmake/headers) — must coexist with conda's
# default libboost, and we want the 1.82-derived ABI everywhere.
fetch_and_install_conda "libboost-1.82.0-h6fcfa73_6.conda"        "${CF}/libboost-1.82.0-h6fcfa73_6.conda"
fetch_and_install_conda "libboost-devel-1.82.0-h00ab1b0_6.conda"  "${CF}/libboost-devel-1.82.0-h00ab1b0_6.conda"

# PCL 1.13 + the matching ros-noetic-pcl-* (build _17 = boost-1.82 family).
fetch_and_install_conda "pcl-1.13.1-h4836831_3.conda"             "${CF}/pcl-1.13.1-h4836831_3.conda"
fetch_and_install_conda "flann-1.9.2-he1b7b50_6.conda"            "${CF}/flann-1.9.2-he1b7b50_6.conda"
fetch_and_install_conda "ros-noetic-pcl-conversions-1.7.4-py311hb8eba80_17.tar.bz2"     "${RB}/ros-noetic-pcl-conversions-1.7.4-py311hb8eba80_17.tar.bz2"
fetch_and_install_conda "ros-noetic-pcl-ros-1.7.4-py311hb8eba80_17.tar.bz2"             "${RB}/ros-noetic-pcl-ros-1.7.4-py311hb8eba80_17.tar.bz2"
fetch_and_install_conda "ros-noetic-pcl-msgs-0.3.0-np126py311h3dde49b_18.conda"         "${RB}/ros-noetic-pcl-msgs-0.3.0-np126py311h3dde49b_18.conda"
fetch_and_install_conda "ros-noetic-depth-image-proc-1.17.0-py311hb8eba80_17.tar.bz2"   "${RB}/ros-noetic-depth-image-proc-1.17.0-py311hb8eba80_17.tar.bz2"

# Remove any stale boost-1.86 CMake configs left by earlier runs. With both
# 1.82 and 1.86 configs present, CMake's find_package picks the newer one and
# bakes 1.86 hard-paths that don't exist into our build artifacts.
rm -rf "${ENV_PREFIX}/lib/cmake/boost"*-1.86.0 \
       "${ENV_PREFIX}/lib/cmake/Boost-1.86.0" \
       "${ENV_PREFIX}/lib/cmake/BoostDetectToolset-1.86.0.cmake" 2>/dev/null || true

# conda-forge's depth_image_proc nodelet has an undeclared dep on the
# OpenCV 4.10 SONAMEs, but the env ships OpenCV 4.9. The two are ABI-compatible
# for the symbols used; bridge the soname gap with symlinks so nodelet loading
# works.
for lib in libopencv_calib3d libopencv_core libopencv_imgproc libopencv_features2d libopencv_flann libopencv_imgcodecs libopencv_highgui libopencv_video libopencv_videoio libopencv_dnn libopencv_objdetect libopencv_ml libopencv_photo libopencv_stitching libopencv_gapi; do
    if [ -f "${ENV_PREFIX}/lib/${lib}.so.409" ] && [ ! -e "${ENV_PREFIX}/lib/${lib}.so.410" ]; then
        ln -s "${lib}.so.409" "${ENV_PREFIX}/lib/${lib}.so.410"
    fi
done

# conda's pcl_conversions/pcl_ros CMake configs list VTK 9.x libraries in the
# link line; we don't have VTK in the env. Strip them so consumers don't fail
# linking. (Pure visualization code paths aren't used by voxblox_ros etc.)
for f in "${ENV_PREFIX}/share/pcl_conversions/cmake/pcl_conversionsConfig.cmake" \
         "${ENV_PREFIX}/share/pcl_ros/cmake/pcl_rosConfig.cmake"; do
    [ -f "$f" ] || continue
    python3 -c "
import re, sys
p = '$f'
s = open(p).read()
s2 = re.sub(r'${ENV_PREFIX}/lib/libvtk[A-Za-z0-9]+-9\.[23]\.so\.1;?', '', s)
if s != s2:
    open(p, 'w').write(s2)
"
done

# 5. Print activation incantation. Do not auto-edit the user's shell rc.
cat <<EOF

Done. To activate the env in your current shell, run:

    export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX}"
    eval "\$('${MAMBA}' shell hook -s bash)"
    micromamba activate ${ENV_NAME}

Inside the activated env, run scripts/build_catkin.sh to build the catkin
packages.
EOF
