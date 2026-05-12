# Kimera Workspace Pipeline Test Plan

End-to-end verification that every component the project's README claims to
produce can actually be produced from a fresh clone of this repo on a
supported host. Each stage has a concrete pass/fail check so failures are
attributable to a specific layer.

## What the project claims to output

| Component | Claimed output |
|-----------|----------------|
| Kimera-VIO | 6-DoF visual-inertial trajectory, IMU bias estimates, sparse landmarks, optional 3D mesh of structural regularities, output logs in `output_logs/` |
| Kimera-RPGO | Robust pose graph optimization: corrected trajectory after loop closures, outlier-rejected factor graph |
| voxblox | Dense volumetric map: TSDF, ESDF, marching-cubes triangle mesh (`.ply`) |
| Kimera-Semantics | Metric-semantic 3D mesh / TSDF (semantic labels per voxel), built on top of voxblox |
| Top-level pipeline | EuRoC stereo+IMU bag → trajectory + dense semantic mesh of the scene |

## Host requirements (known good)

- Ubuntu 20.04 with ROS Noetic (upstream-supported), **or** Ubuntu 22.04 with
  the RoboStack conda env in `scripts/kimera_ros.env.yaml` (verified end-to-end
  on this host).
- For the 22.04 path: `micromamba` (installed automatically by
  `scripts/setup_ros_env.sh`) and ≥ 6 GB free under `$HOME` for the
  `kimera_ros` env at `$MAMBA_ROOT_PREFIX/envs/kimera_ros`.
- ≥ 60 GB free disk (deps ~5 GB, EuRoC zips ~29 GB, extracted ~29 GB, build ~5 GB)
- ≥ 16 GB RAM for `make -j$(nproc)`

**Ubuntu 22.04 status (resolved in this workspace):**
1. Eigen 3.4 + GCC 11 ADL errors in `unsupported/Eigen/SpecialFunctions` —
   bypassed by pinning **GTSAM 4.2** (matches upstream `Dockerfile_20_04`)
   instead of 4.1.1. The 4.2 headers do not pull the broken
   `unsupported/Eigen/SpecialFunctions` import path.
2. `cv::viz::Viz3d` not declared — fixed by an explicit
   `#include <opencv2/viz.hpp>` in 7 Kimera-VIO files. The patches live on the
   submodule branch `local/ubuntu22-fixes`; `opencv_viz` is shipped on 22.04,
   only the include was missing.

With these in place a clean Kimera-VIO build (library + `stereoVIOEuroc`)
succeeds natively on Ubuntu 22.04 with `-DKIMERA_BUILD_TESTS=OFF`. The unit
tests (`testKimeraVIO`) still fail for unrelated upstream code rot
(`reference to 'Tracker' is ambiguous`, missing `tracker_` field) — out of
scope for this plan.

---

## Stage 0 — Repo bootstrap (clones)

```bash
git clone <this-repo> kimera_workspace && cd kimera_workspace
./scripts/setup_workspace.sh
```

**Pass criteria**
- `git submodule status` lists 5 submodules at the recorded SHAs:
  Kimera-VIO, Kimera-Semantics, Kimera-RPGO, voxblox, kalibr.
- No "fatal" errors from git.

## Stage 1 — System & from-source dependencies

```bash
sudo ./scripts/install_dependencies.sh
```

**Pass criteria** (script now runs the three from-source builds in parallel and
writes per-build status files to `/tmp/kimera_build_logs/*.status`)
- `apt-get install` returns 0.
- `gtsam.status`, `opengv.status`, `dbow2.status` all read `OK`.
- `ldconfig -p` shows `libgtsam`, `libopengv`, `libDBoW2`.

**Verified in this session:** all three built and installed cleanly in parallel.

## Stage 2 — Dataset acquisition

```bash
./scripts/download_datasets.sh
```

**Pass criteria**
- `datasets/euroc/{machine_hall,vicon_room1,vicon_room2,calibration_datasets}.zip`
  exist with sizes matching the bitstream `sizeBytes` from the DSpace API
  (≈ 12.7 / 6.0 / 6.0 / 4.4 GB).
- `datasets/euroc/.<name>.extracted` markers present for each zip.
- Sequence folders like `datasets/euroc/vicon_room1/V1_01_easy/mav0/{cam0,cam1,imu0,state_groundtruth_estimate0}/data.csv` are populated.

**Conversion sub-stage** (only if a ROS env with kalibr is sourced)
- `datasets/euroc/V1_01_easy.bag`, `MH_01_easy.bag`, … exist.
- `rosbag info <bag>` shows topics `/cam0/image_raw`, `/cam1/image_raw`, `/imu0`.
- If kalibr is not on `PATH` and `rosrun` cannot find it, the script logs an
  instructive skip — not a failure.

**Verified in this session:** all four bitstream URLs return HTTP 206 and the
first ~80 MB of `calibration_datasets.zip` parsed as a valid PKZIP archive.
Full download/conversion not run (disk + no ROS in this env).

## Stage 3 — Component builds

Each component is plain CMake (the ROS-only ones additionally need a sourced
catkin workspace).

### 3a. Kimera-RPGO (plain CMake, depends on GTSAM)
```bash
cmake -S src/Kimera-RPGO -B src/Kimera-RPGO/build -DCMAKE_BUILD_TYPE=Release
cmake --build src/Kimera-RPGO/build -j$(nproc)
sudo cmake --install src/Kimera-RPGO/build
```
**Pass:** `libKimeraRPGO.so` in `/usr/local/lib`, `RpgoReadme` example binary
runs without error on `examples/example_1d.g2o`.

**Verified in this session.**

### 3b. Kimera-VIO (plain CMake, depends on RPGO + GTSAM + OpenGV + DBoW2 + OpenCV-viz)
```bash
cmake -S src/Kimera-VIO -B src/Kimera-VIO/build \
    -DCMAKE_BUILD_TYPE=Release -DKIMERA_BUILD_TESTS=OFF
cmake --build src/Kimera-VIO/build -j$(nproc)
```
**Pass:** `build/libkimera_vio.so` + `build/stereoVIOEuroc` produced.

**Verified in this session on Ubuntu 22.04** with GTSAM 4.2 and the
`local/ubuntu22-fixes` submodule branch.

### 3b1. Kimera-VIO smoke run on the bundled MicroEuroc dataset

No 29 GB download required — Kimera-VIO ships ~95 frames of EuRoC under
`tests/data/MicroEurocDataset/`.

```bash
cd src/Kimera-VIO
xvfb-run -a bash scripts/stereoVIOEuroc.bash \
    -p "$(pwd)/tests/data/MicroEurocDataset" -log
```

`xvfb-run` is required because Kimera-VIO's 3D visualizer initializes a VTK
window unconditionally and aborts on `bad X server connection` in headless
environments.

**Pass:**
- Process logs `Pipeline successful? Yes!` and exits 0.
- `output_logs/traj_vio.csv` exists, has the 17-column TUM-style header
  (`#timestamp,x,y,z,qw,qx,qy,qz,vx,vy,vz,bgx,bgy,bgz,bax,bay,baz`), and at
  least one data row beyond the header.
- `output_logs/output_frontend_stats.csv` is non-empty.

**Verified in this session.**

### 3c. voxblox + Kimera-Semantics (catkin, RoboStack env)
Prereq: `scripts/setup_ros_env.sh` has run and the `kimera_ros` env is
active (`$ROS_DISTRO == noetic`, `$CONDA_PREFIX` points at the env).
```bash
./scripts/setup_workspace.sh                    # vcs imports helper packages
KIMERA_WORKSPACE_SKIP_VOXBLOX_TESTS=1 ./scripts/build_catkin.sh
```
**Pass:**
- `catkin build` exits 0 with `voxblox`, `voxblox_ros`, `voxblox_msgs`,
  `voxblox_rviz_plugin`, `kimera_semantics`, `kimera_semantics_ros` all in
  the "Finished" summary.
- `devel/lib/voxblox_ros/{tsdf_server,esdf_server,intensity_server}`
  exist.
- `devel/lib/kimera_semantics_ros/{kimera_semantics_node,kimera_semantics_rosbag}`
  exist.

**Verified in this session on Ubuntu 22.04** via the RoboStack env with
local patches to `src/voxblox` and `src/Kimera-Semantics` on the
`local/ubuntu22-robostack-fixes` branches of each submodule. See
[`docs/patches.md`](docs/patches.md) for the patch rationale (conda-forge
glog 0.7 export-macro guard, abseil 20240116 needing C++17, gflags
namespace, glog-link for executables).

### 3d. kalibr (catkin) — needed only for `.bag` conversion
```bash
./scripts/build_catkin.sh   # picks up kalibr along with the other packages
source devel/setup.bash
rosrun kalibr kalibr_bagcreater --help
```
**Pass:** `kalibr_bagcreater --help` prints usage with no Python import
errors.

### 4d. Kimera-Semantics demo bag → semantic mesh
Smallest end-to-end path through the project's claimed outputs. Uses the
demo bag fetched by `scripts/download_datasets.sh` (gdown,
`1SG8cfJ6JEfY2PGXcxDPAMYzCcGBEh4Qq`, ~1.9 GB).

```bash
source devel/setup.bash
nohup roscore > /tmp/roscore.log 2>&1 &
sleep 5
roslaunch kimera_semantics_ros kimera_semantics.launch \
    play_bag:=true \
    bag_file:=$(pwd)/datasets/kimera_semantics_demo.bag \
    metric_semantic_reconstruction:=true \
    run_stereo_dense:=false &
# Wait for "Done." in the launch's stderr (rosbag play finishes), then:
rosservice call /kimera_semantics_node/generate_mesh "{}"
```

**Pass:**
- `src/Kimera-Semantics/kimera_semantics_ros/mesh_results/tesse_*.ply`
  exists, > 0 bytes.
- Header reports a non-trivial vertex/face count:
  ```bash
  head -c 1024 src/Kimera-Semantics/kimera_semantics_ros/mesh_results/tesse_*.ply \
      | grep -E "element vertex|element face"
  # element vertex 262176
  # element face   304672
  ```
- The PLY header contains `property uchar red/green/blue/alpha` — per-vertex
  semantic colors are populated.
- The launch's stdout reports many `Integrating a pointcloud with N points`
  log lines (depth_image_proc nodelet must have started — requires the
  conda env's `libopencv_*.so.410` symlinks to OpenCV 4.9 to be in place,
  applied by `scripts/setup_ros_env.sh`).

**Verified in this session.** Produced a 24 MB mesh
(262 176 vertices, 304 672 faces, RGBA semantic colors) from the demo bag.

## Stage 4 — Functional tests per component

### 4a. Kimera-VIO on EuRoC V1_01_easy → trajectory output
```bash
cd src/Kimera-VIO
./scripts/stereoVIOEuroc.bash -p ../../datasets/euroc/vicon_room1/V1_01_easy -log
```
**Pass:**
- Process exits 0.
- `output_logs/Frontend/output_frontend_stats.csv` populated, ≥ N rows.
- `output_logs/Backend/traj_vio.csv` is a 7-column TUM-style trajectory and the
  RMS ATE against `state_groundtruth_estimate0/data.csv` (e.g. via `evo_ape`)
  is below the threshold from the upstream Jenkinsfile (V1_01: ATE < ~0.10 m).
- If `--use_lcd=true` is set, loop closures appear in the backend log.

### 4b. Kimera-RPGO standalone → robust pose graph optimization
```bash
./src/Kimera-RPGO/build/RpgoReadme src/Kimera-RPGO/examples/example_1d.g2o
```
**Pass:** prints "Optimization complete" and the optimized cost is lower than
the initial cost. (For a real test, also run on a g2o file containing
fabricated outliers and confirm RPGO rejects them.)

### 4c. voxblox on EuRoC bag → TSDF + ESDF + mesh
```bash
roslaunch voxblox_ros euroc_dataset.launch bag_file:=$(pwd)/datasets/euroc/V1_01_easy.bag
rosservice call /voxblox_node/generate_mesh
```
**Pass:** `cow_and_lady_mesh.ply` (or configured output path) is a valid PLY
mesh > 0 vertices; ESDF service `/voxblox_node/save_map` writes a non-empty
`.vxblx`.

### 4d. Kimera-Semantics on demo bag → semantic mesh
```bash
roslaunch kimera_semantics_ros kimera_semantics.launch \
    play_bag:=true bag_file:=$(pwd)/datasets/kimera_semantics_demo.bag
rosservice call /kimera_semantics_node/generate_mesh
```
**Pass:** PLY mesh contains per-vertex color encoding semantic labels;
`rostopic echo /semantic_pointcloud` emits messages while playing.

### 4e. End-to-end: VIO → Semantics on uHumans2
The full Kimera demo (Kimera-VIO-ROS + Kimera-Semantics together) lives in the
`Kimera-VIO-ROS` repo, which is **not** currently a submodule. Adding it as
`src/Kimera-VIO-ROS` is required to test the full claim "real-time
metric-semantic SLAM."

## Stage 5 — Acceptance gate

The pipeline is "working" when all of the following are produced from one
fresh clone:

- [ ] Trajectory CSV from Kimera-VIO on V1_01_easy with ATE < threshold.
- [ ] Optimized trajectory from Kimera-RPGO on a graph with synthetic outliers.
- [ ] Voxblox `.ply` mesh + `.vxblx` ESDF from V1_01_easy.
- [ ] Kimera-Semantics semantic `.ply` mesh from the demo bag.
- [ ] (Stretch) End-to-end Kimera-VIO-ROS + Kimera-Semantics on uHumans2.

## Gaps to close before this plan can run unattended

1. **Add `Kimera-VIO-ROS` submodule** for the end-to-end test (Stage 4e).
2. **Pin a host**: the README implies "standalone non-ROS", but Kimera-Semantics
   and voxblox are catkin packages — clarify whether the workspace targets
   ROS Noetic or only the non-ROS Kimera-VIO core, and adjust the README.
3. **Patch or document Ubuntu 22.04 path**: either commit a small CMake patch
   adding `-fpermissive` and stubbing `cv::viz` usage, or add a check in
   `install_dependencies.sh` that refuses to run outside 20.04.
4. **Numeric thresholds**: codify ATE/RMS thresholds per sequence in
   `scripts/test_components.sh` so Stage 4 can be evaluated automatically.
5. **uHumans2 download**: the placeholder `gdown --id 1-28v8-…` in
   `download_datasets.sh` is not a real ID; replace with the real Drive ID or
   remove the entry.
