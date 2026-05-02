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

- Ubuntu 20.04 with ROS Noetic (the upstream-supported configuration)
- ≥ 60 GB free disk (deps ~5 GB, EuRoC zips ~29 GB, extracted ~29 GB, build ~5 GB)
- ≥ 16 GB RAM for `make -j$(nproc)`

**Known incompatibilities on Ubuntu 22.04** (observed in this session):
1. Eigen 3.4 + GCC 11 strict ADL: `unsupported/Eigen/SpecialFunctions` fails with
   `pchebevl`/`pcmp_le` not found. Workaround: `-fpermissive` or pin Eigen 3.3.
2. `cv::viz::Viz3d` not declared: `opencv_viz` is not built in
   `libopencv-contrib-dev` 4.5.4 on 22.04. Either build OpenCV from source with
   VTK + `-DBUILD_opencv_viz=ON`, or stub out the `MeshOptimization` /
   `RgbdCamera` viz code.

The plan below assumes 20.04. Steps for 22.04 require the workarounds above.

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
cmake -S src/Kimera-VIO -B src/Kimera-VIO/build -DCMAKE_BUILD_TYPE=Release
cmake --build src/Kimera-VIO/build -j$(nproc)
```
**Pass:** binaries `build/stereoVIOEuroc`, `build/stereoVIOEurocCsv` produced;
`ctest` from build dir reports all unit tests passing.

**Status in this session:** failed on Ubuntu 22.04 — see incompatibilities
above.

### 3c. voxblox (catkin) and Kimera-Semantics (catkin)
Requires a catkin workspace and ROS Noetic. From the workspace root:
```bash
source /opt/ros/noetic/setup.bash
catkin build voxblox_ros kimera_semantics_ros
```
**Pass:** `devel/lib/voxblox_ros/voxblox_node`,
`devel/lib/kimera_semantics_ros/kimera_semantics_node` exist.

### 3d. kalibr (catkin) — needed only for `.bag` conversion
```bash
catkin build kalibr
rosrun kalibr kalibr_bagcreater --help
```

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
