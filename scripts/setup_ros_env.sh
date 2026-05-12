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

# 4. Print activation incantation. Do not auto-edit the user's shell rc.
cat <<EOF

Done. To activate the env in your current shell, run:

    export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX}"
    eval "\$('${MAMBA}' shell hook -s bash)"
    micromamba activate ${ENV_NAME}

Inside the activated env, run scripts/build_catkin.sh to build the catkin
packages.
EOF
