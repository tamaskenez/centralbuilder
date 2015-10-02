#     add_pkg(<name>
#             [GIT_REPOSITORY|GIT_URL] <url>
#             [CMAKE_ARGS <args..>]
#             [SOURCE_DIR <source-dir>]
#             [DEPENDS <dependencies...>])
#
# Use add_pkg in the package registry files to specify packages.
# The parameters are based on the ExternalProject_Add's parameters:
#
# <name> should be the find-package-name of the package. CentralBuilder will
#   test each package with a tentative `find_package`
#
# GIT_REPOSITORY which can be shortened to GIT_URL specifies the git
#   repository's URL. This is the only mandatory parameter.
#
# CMAKE_ARGS is a list of options that will be passed to the `cmake` command
#   when the package's project will be configured.
#   Don't specify global options here (see the following list). Global options
#   must be set with the GLOBAL_CMAKE_ARGS parameter of CentralBuilder.cmake
#   Usual global options are:
#   - CMAKE_BUILD_TYPE
#   - CMAKE_GENERATOR, CMAKE_GENERATOR_TOOLSET, CMAKE_GENERATOR_PLATFORM
#     (-G, -T, -A) and CMAKE_TOOLCHAIN
#
# SOURCE_DIR is a relative path, the location of the package's CMakeLists.txt
#   relative to the repo's root.
#
# DEPENDS is a list of project names, the dependencies of this package. This
#   parameter is ignored for now.
#
function(add_pkg NAME)
  # test list compatibility
  set(s ${NAME})
  list(LENGTH s l)
  if(NOT l EQUAL 1)
    message(FATAL_ERROR "'${NAME}' is an invalid name for a package")
  endif()
  list(APPEND PKG_NAMES "${NAME}")
  set(PKG_NAMES ${PKG_NAMES} PARENT_SCOPE)
  # quoting ARGN is neccessary to preserve \; within list items
  # for example CMAKE_ARGS "-DTHIS_VAR=contains\;a\;list"
  set(PKG_ARGS_${NAME} "${ARGN}" PARENT_SCOPE)
endfunction()
