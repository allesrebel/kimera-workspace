#!/bin/bash
export MAMBA_ROOT_PREFIX="/opt/rebel/micromamba"
eval "$("/root/.local/bin/micromamba" shell hook -s bash)"
micromamba activate kimera_ros
bash scripts/build_catkin.sh
