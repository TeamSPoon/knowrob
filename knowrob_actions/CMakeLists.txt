
cmake_minimum_required(VERSION 2.8.3)
project(knowrob_actions)

find_package(catkin REQUIRED COMPONENTS knowrob_common knowrob_objects)


catkin_package(
    DEPENDS knowrob_common knowrob_objects
)