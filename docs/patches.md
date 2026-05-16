# Local patches to Kimera submodules for the RoboStack/conda-forge build

The catkin half of this workspace runs inside a RoboStack
(`ros-noetic-*` on conda-forge) env on Ubuntu 22.04. The conda-forge
toolchain pins (glog 0.7, gflags 2.2, abseil 20240116 via libprotobuf 4.25,
boost 1.82, pcl 1.13, gcc 12) differ from upstream Kimera's tested 20.04 /
apt ROS Noetic environment. The submodules need a few small source patches
to build under this env. The patches live on
`local/ubuntu22-robostack-fixes` branches inside the affected submodules
and are pinned by the parent repo's submodule SHAs.

Affected submodules:
- `src/voxblox` — `local/ubuntu22-robostack-fixes`
- `src/Kimera-Semantics` — `local/ubuntu22-robostack-fixes`
- `src/Kimera-VIO` — `local/ubuntu22-fixes` (separate older branch; covers
  the native non-ROS build, documented in commit `f9baa03`)

## Patch 1 — C++17 standard

**Files:** `voxblox/CMakeLists.txt`, `voxblox_ros/CMakeLists.txt`,
`kimera_semantics/CMakeLists.txt`, `kimera_semantics_ros/CMakeLists.txt`.

**Why:** conda-forge's libprotobuf 4.25 transitively pulls abseil
`lts_20240116`, which hard-requires C++17. Upstream voxblox declares
`-std=c++11` and kimera_semantics doesn't pin a standard; mixing C++14 (or
older) with abseil 20240116 fails with template-resolution errors in
`absl::strings/cord.h` (`FunctionRef<void(string_view)>` cannot bind a
`[](string_view)` lambda).

**Edit:** bump or add near the top of each CMakeLists:
```cmake
add_definitions(-std=c++17)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
```

## Patch 2 — `GLOG_USE_GLOG_EXPORT` define

**Files:** same four CMakeLists as Patch 1.

**Why:** conda-forge glog 0.7 wraps every public symbol in `GLOG_EXPORT`,
which expands to an `__attribute__((visibility(...)))` only when
`GLOG_USE_GLOG_EXPORT` is `#define`d at the consumer level. Without it the
glog headers compile but the *use sites* see a hidden-visibility decl, so
`google::InitGoogleLogging` and friends fail to link as
`undefined reference`. The header itself errors out with
`<glog/logging.h> was not included correctly` to make the missing define
explicit.

**Edit:** add to each CMakeLists alongside Patch 1:
```cmake
add_definitions(-DGLOG_USE_GLOG_EXPORT)
```

## Patch 3 — Explicit `glog` link for executables

**Files:** `voxblox_ros/CMakeLists.txt`, `kimera_semantics_ros/CMakeLists.txt`.

**Why:** `cs_add_executable` from catkin_simple inherits catkin
`*_INCLUDE_DIRS` but not always `*_LIBRARIES`. The library targets
(`libvoxblox.so`, `libvoxblox_ros.so`, `libkimera_semantics.so`) carry
glog via their transitive deps, but the *executable* `main()`s use
`google::InitGoogleLogging`, `google::InstallFailureSignalHandler`, etc.
directly and need glog on their own link line under conda-forge glog 0.7.

**Edit:** append `glog` to each affected `target_link_libraries`:
```cmake
target_link_libraries(tsdf_server          ${PROJECT_NAME} glog)
target_link_libraries(esdf_server          ${PROJECT_NAME} glog)
target_link_libraries(intensity_server     ${PROJECT_NAME} glog)
target_link_libraries(kimera_semantics_node   ${PROJECT_NAME} glog)
target_link_libraries(kimera_semantics_rosbag ${PROJECT_NAME} glog)
target_link_libraries(semantic_simulator_eval ${PROJECT_NAME} ${PCL_LIBRARIES} glog)
```

## Patch 4 — Skip glog-linking test executables in voxblox

**Files:** `voxblox/CMakeLists.txt`, `voxblox_ros/CMakeLists.txt`.

**Why:** voxblox ships `tsdf_to_esdf`, `test_load_esdf` (in `voxblox/`)
and `voxblox_eval`, `simulation_eval`, `visualize_tsdf` (in `voxblox_ros/`)
that include `<glog/logging.h>` *before* the per-package
`add_definitions(-DGLOG_USE_GLOG_EXPORT)` takes effect for those
translation units. They aren't needed by the runtime nodes or the demo
pipeline.

**Edit:** wrap each `add_executable` block in
```cmake
if(NOT DEFINED ENV{KIMERA_WORKSPACE_SKIP_VOXBLOX_TESTS})
  …
endif()
```
and set `KIMERA_WORKSPACE_SKIP_VOXBLOX_TESTS=1` when invoking
`scripts/build_catkin.sh`. `scripts/build_catkin.sh` does this
automatically.

## Patch 5 — Explicit `#include <gflags/gflags.h>` in Kimera-Semantics mains

**Files:** `kimera_semantics_ros/src/kimera_semantics_node.cpp`,
`kimera_semantics_ros/src/kimera_semantics_rosbag.cpp`.

**Why:** the upstream sources call `google::ParseCommandLineFlags` (note:
conda-forge gflags defines `GFLAGS_NAMESPACE=google`, so `google::` is
correct here — *not* `gflags::`), but rely on the gflags header being
included transitively via another include. Under newer ROS Noetic + gflags
2.2 that transitive chain no longer pulls `<gflags/gflags.h>`, so the
call site fails with `'ParseCommandLineFlags' is not a member of 'google'`.

**Edit:** add an explicit `#include <gflags/gflags.h>` near the top of each
main file.

## Patch 6 — Kimera-VIO: disable Pangolin, add explicit includes, autoInit=1

**Files:** `src/Kimera-VIO/CMakeLists.txt`,
`src/Kimera-VIO/include/kimera-vio/utils/UtilsNumerical.h`,
`src/Kimera-VIO/params/Euroc/BackendParams.yaml`.

**Why:**
- `CMakeLists.txt`: pin `Pangolin_FOUND=FALSE` in source so consumers that
  don't pass `-DCMAKE_DISABLE_FIND_PACKAGE_Pangolin=ON` still build.
- `UtilsNumerical.h`: explicit `<vector>` and `<cstdint>` includes for
  GCC 12 / glibc 2.35 (older versions pulled them transitively).
- `BackendParams.yaml`: bump `autoInitialize: 0 → 1`. The Kimera-VIO-ROS
  data provider hard-aborts on `autoInitialize=0` when no
  `ground_truth_odometry_rosbag_topic` is given, which the demo bag
  doesn't ship. The native `stereoVIOEuroc` CLI is unaffected.

## Patch 7 — Kimera-VIO-ROS: deref PointCloudXYZRGB::Ptr before publish

**Files:** `src/Kimera-VIO-ROS/src/RosVisualizer.cpp`.

**Why:** modern PCL (1.13+) uses `std::shared_ptr` for the
`PointCloud<T>::Ptr` alias, but `ros::Publisher::publish<T>()` only has ROS
message_traits registered for the bare `pcl::PointCloud<T>` (and
historically for `boost::shared_ptr<>`). Passing a `std::shared_ptr<>`
fails to compile with "no member `__getMD5Sum` / `__getDataType` / …" on
the shared_ptr type. Dereferencing (`publish(*msg)`) picks the correct
template specialization; the on-the-wire message is identical.

## cv_bridge source build (not a "patch" but a vendor swap)

**Tree:** `src/vision_opencv/` — fresh clone of
`ros-perception/vision_opencv` (noetic branch) added by
`scripts/setup_workspace.sh`. Provides catkin sources for `cv_bridge` and
`image_geometry`.

**Why:** conda-forge's `ros-noetic-cv-bridge` binary links against conda's
OpenCV 4.9. The natively-built `libkimera_vio.so` and the catkin packages
we ship link against system OpenCV 4.5 (which has the `cv::viz` module
Kimera-VIO uses extensively; conda doesn't ship `opencv_viz`). Two OpenCV
versions in one process produced cv::Mat ABI mismatch crashes when running
`kimera_vio_ros_node`. Rebuilding cv_bridge from source against system
OpenCV 4.5 — and letting catkin's develspace shadow the conda binary —
keeps the OpenCV ABI consistent end-to-end through the
`kimera_vio_ros_node` binary.

The `vision_opencv/opencv_tests/` and `vision_opencv/vision_opencv/`
metapackage dirs are CATKIN_IGNOREd by `setup_workspace.sh` to avoid
duplicate-package-name conflicts with catkin_tools.

## Why not git submodules to forks?

Long-term, forking voxblox and Kimera-Semantics and pointing the
submodules at `MIT-SPARK/*` (or `ethz-asl/*`) forks with these patches
applied would be cleaner. For now they live on `local/*` branches inside
the existing submodules, with the parent repo's submodule SHAs pinned to
those local commits. Re-running `git submodule update --init` will not
clobber the local branches because the parent SHA already points at them.

The same pattern is used for `src/Kimera-VIO`'s
`local/ubuntu22-fixes` branch (covers the native non-ROS path, established
in commit `f9baa03`).
