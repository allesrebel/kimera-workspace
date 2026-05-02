cmake_minimum_required(VERSION 3.10)
project(kimera_workspace)

# Add subdirectories for each component
# Note: They must be added in an order that respects dependencies
# RPGO is a dependency for VIO

add_subdirectory(src/Kimera-RPGO)
add_subdirectory(src/Kimera-VIO)

# Kimera-Semantics, Voxblox, and Kalibr are catkin (ROS) packages, so they
# do not build directly with add_subdirectory. They live under src/ to be
# picked up by a catkin workspace build (catkin build / catkin_make).
# Kalibr provides kalibr_bagcreater, used by scripts/download_datasets.sh
# to convert the EuRoC ASL-format zips into ROS bags.

# add_subdirectory(src/voxblox)
# add_subdirectory(src/Kimera-Semantics)
# add_subdirectory(src/kalibr)
