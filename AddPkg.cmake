#     add_pkg(<name>
#             <other-options-for-ExternalProject_Add>)
#
# Use add_pkg in the package registry files to specify packages.
#
# For the other-options see:
# https://cmake.org/cmake/help/latest/module/ExternalProject.html
#
# Notes about certain parameters:
#
# - <name> must be the find-package-name of the package. It's because
#   the CentralBuilder will test each package with tentative `find_package`
# - don't specify global options (see the following list) because the
#   CentralBuilder project will set those uniformly for all projects.
#   Such global options are:
#   - CMAKE_BUILD_TYPE
#   - CMAKE_GENERATOR, CMAKE_GENERATOR_TOOLSET, CMAKE_GENERATOR_PLATFORM
#     (-G, -T, -A)
#   - CMAKE_TOOLCHAIN
#
# Example for git repos:
#
#     add_pkg(<name> GIT_REPOSITORY <url>
#             [GIT_TAG <branch-tag-commit>]
#             [CMAKE_ARGS <args...>])
#             [SOURCE_DIR <source-dir>])
#
# Example for tar.gz distro:
#
#     add_pkg(<name> URL <url>
#             [CMAKE_ARGS <args...>])
#             [SOURCE_DIR <source-dir>])
#
function(add_pkg NAME)
  # test list compatibility
  set(s ${NAME})
  list(LENGTH s l)
  if(NOT l EQUAL 1)
    message(FATAL_ERROR "'${NAME}' is an invalid name for a package")
  endif()
  list(APPEND PKG_NAMES "${NAME}")
  set(PKG_NAMES ${PKG_NAMES} CACHE INTERNAL "" FORCE)
  set(PKG_ARGS_${NAME} ${ARGN} CACHE INTERNAL "" FORCE)
endfunction()
