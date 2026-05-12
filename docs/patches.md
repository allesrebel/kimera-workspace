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
