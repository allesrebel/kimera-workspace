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
Installs micromamba (if missing) and creates/updates the `kimera_ros` env from `scripts/kimera_ros.env.yaml`. Idempotent.

### Workspace Setup & Patching
To clone submodules, apply workspace git patches (handling glog version conflicts, Boost compatibility, and forward declarations), clone vision-opencv libraries, and automatically configure `CATKIN_IGNORE` files to ignore duplicate packages in nested submodules, run the automated setup script:
```bash
./run_setup_workspace_in_env.sh
```

### Build the Workspace
To build the entire 68-package workspace (including native VIO components and ROS nodes) inside the environment, run:
```bash
./run_build_catkin_in_env.sh
```
This automatically configures the catkin workspace with environment shims (overriding glog target exports to developer libraries and adjusting GTSAM compiler flags) and executes the build in parallel.

### Run the End-to-End Demo
To verify the full semantics reconstruction pipeline on the demo dataset bag:
1. Ensure the datasets are downloaded via `./scripts/download_datasets.sh`.
2. Source the devel space in your shell:
   ```bash
   # Make sure you are inside the micromamba env
   micromamba activate kimera_ros
   source devel/setup.bash
   ```
3. Run the ROS bags and nodes:
   ```bash
   roslaunch kimera_semantics_ros kimera_semantics.launch \
       play_bag:=true \
       bag_file:=$(pwd)/datasets/kimera_semantics_demo.bag \
       metric_semantic_reconstruction:=true \
       run_stereo_dense:=false
   ```
4. In another terminal, call the mesh generation service:
   ```bash
   rosservice call /kimera_semantics_node/generate_mesh "{}"
   ```

This generates a per-vertex colored 3D semantic mesh under `src/Kimera-Semantics/kimera_semantics_ros/mesh_results/tesse_*.ply` (~24 MB, 261,832 vertices, 304,142 faces).

### Cleanup
To cleanly shut down the active ROS processes and prevent nodelet manager name duplication errors on subsequent runs, use:
```bash
pkill -9 -f "roscore|rosmaster|roslaunch|nodelet|kimera_semantics|rosout" || true
```

## References
- [MIT-SPARK/Kimera](https://github.com/MIT-SPARK/Kimera)
- [Kimera-VIO](https://github.com/MIT-SPARK/Kimera-VIO)
- [Kimera-Semantics](https://github.com/MIT-SPARK/Kimera-Semantics)
