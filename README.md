# Kimera Workspace

This workspace contains a standalone C++ (non-ROS) setup for the **Kimera** pipeline, a real-time metric-semantic SLAM system developed by MIT SPARK Lab.

## Project Structure

- `src/`: Submodules for core Kimera components.
  - `Kimera-VIO`: Visual-Inertial Odometry engine.
  - `Kimera-RPGO`: Robust Pose Graph Optimization.
  - `Kimera-Semantics`: Metric-semantic 3D reconstruction.
  - `voxblox`: Underlying volumetric mapping library.
- `scripts/`: Automation scripts for environment setup and data acquisition.
- `datasets/`: Storage for benchmark datasets (EuRoC, uHumans).
- `CMakeLists.txt`: Root CMake file to build the entire pipeline.

## Setup Instructions

### 1. Prerequisites & Dependencies
The workspace requires several system libraries and specific versions of GTSAM and OpenGV. These are handled automatically by the installation script.

```bash
chmod +x scripts/*.sh
./scripts/install_dependencies.sh
```
*Note: This script will build GTSAM, OpenGV, and DBoW2 from source to ensure compatibility.*

### 2. Initialize Workspace
Clone all necessary submodules and initialize the internal git structure:

```bash
./scripts/setup_workspace.sh
```

### 3. Download Datasets
Fetch the standard benchmarks for testing the pipeline:

```bash
./scripts/download_datasets.sh
```
Included datasets:
- **EuRoC MAV**: V1_01_easy
- **Kimera-Semantics**: Demo bag
- **uHumans2**: Office sample

### 4. Build & Test
Compile the components and run their respective unit tests to verify the installation:

```bash
# Run unit tests for individual components
./scripts/test_components.sh

# Build the entire workspace
mkdir build && cd build
cmake ..
make -j$(nproc)
```

## Running Kimera
After building, you can run the standalone examples located in the `build/` directory. For example, to run the EuRoC benchmark:

```bash
cd build/src/Kimera-VIO
./stereoVIOEuroc --dataset_path=../../datasets/V1_01_easy
```

## Building the ROS pipeline (catkin half) — Ubuntu 22.04 / non-Docker

The workspace ships two parallel install models:

| Path | What you get | When to use |
|------|--------------|-------------|
| Native (`scripts/install_dependencies.sh` + per-component CMake) | `libkimera_vio.so` + `stereoVIOEuroc` CLI in `src/Kimera-VIO/build/`. Runs offline on EuRoC CSV/image folders. No ROS. | Trajectory-only experiments, regression on the bundled MicroEuroc data, CI without a ROS install. |
| ROS / catkin (this section) | `tsdf_server`, `esdf_server`, `kimera_semantics_node`, etc. under `devel/lib/`. Consumes `.bag` files, publishes meshes / TFs over rostopics. | Dense mapping, semantic mesh, end-to-end VIO→Semantics demo. |

ROS 1 has no native Ubuntu 22.04 build, so the catkin half runs inside a
[RoboStack](https://robostack.github.io/) conda env (`ros-noetic-*` packages
from conda-forge). The native build above is **not** affected.

### One-time env install
```bash
./scripts/setup_ros_env.sh
```
Installs micromamba (if missing) and creates/updates the `kimera_ros` env
from `scripts/kimera_ros.env.yaml`. Idempotent.

### Activate the env (every new shell)
```bash
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
eval "$("$HOME/.local/bin/micromamba" shell hook -s bash)"
micromamba activate kimera_ros
```

After activation `echo $ROS_DISTRO` should print `noetic` and `which catkin`
should resolve under `$CONDA_PREFIX/bin`.

### Fetch ETHZ-ASL helper catkin packages
The helper packages (catkin_simple, eigen_catkin, glog_catkin, minkindr,
mesh_rviz_plugins, etc.) are pulled by `vcstool` into `src/` (not git
submodules; listed in `.gitignore`). `setup_workspace.sh` runs the imports
automatically when `vcs` is on PATH (which it is inside `kimera_ros`):
```bash
./scripts/setup_workspace.sh
```

### Build the catkin workspace
```bash
KIMERA_WORKSPACE_SKIP_VOXBLOX_TESTS=1 ./scripts/build_catkin.sh
```
The env var skips a handful of voxblox test executables that link
`glog::glog` directly and fail under conda-forge glog 0.7 — runtime nodes
are unaffected. See `docs/patches.md` for the full patch rationale.

### Run the end-to-end demo
```bash
source devel/setup.bash
roslaunch kimera_semantics_ros kimera_semantics.launch \
    play_bag:=true \
    bag_file:=$(pwd)/datasets/kimera_semantics_demo.bag \
    metric_semantic_reconstruction:=true \
    run_stereo_dense:=false
# After bag finishes:
rosservice call /kimera_semantics_node/generate_mesh "{}"
```
Produces a semantic `.ply` mesh under
`src/Kimera-Semantics/kimera_semantics_ros/mesh_results/tesse_*.ply` —
~24 MB, 262 k vertices, 305 k faces, per-vertex semantic colors.

To return to the native CLI, `micromamba deactivate` — the env's
`LD_LIBRARY_PATH`/`PATH` shims drop off and the `/usr/local` toolchain
returns.

## References
- [MIT-SPARK/Kimera](https://github.com/MIT-SPARK/Kimera)
- [Kimera-VIO](https://github.com/MIT-SPARK/Kimera-VIO)
- [Kimera-Semantics](https://github.com/MIT-SPARK/Kimera-Semantics)
