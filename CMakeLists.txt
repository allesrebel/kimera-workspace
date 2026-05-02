cmake_minimum_required(VERSION 3.10)
project(kimera_workspace)

# Add subdirectories for each component
# Note: They must be added in an order that respects dependencies
# RPGO is a dependency for VIO

add_subdirectory(src/Kimera-RPGO)
add_subdirectory(src/Kimera-VIO)

# Kimera-Semantics and Voxblox are typically ROS packages, 
# so they might not build directly with add_subdirectory if they use catkin.
# However, for a standalone workspace, we include them in the src folder.

# add_subdirectory(src/voxblox)
# add_subdirectory(src/Kimera-Semantics)
