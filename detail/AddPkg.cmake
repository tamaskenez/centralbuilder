#     add_pkg(<name>
#             [GIT_REPOSITORY|GIT_URL] <url>
#             [GIT_TAG <branch/tag/commit]
#             [CMAKE_ARGS <args..>]
#             [SOURCE_DIR <source-dir>]
#             [DEPENDS <dependencies...>]
#             [NEST])
#
# For detailed information see README.md
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
# The optional GIT_TAG is followed by a branch name, tag or SHA.
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
# If NEST is specified then the package will be installed to `<prefix>/<name>`
# instead of `<prefix>`. The config-modules of the package will be exposed in
# `<prefix>` with the following method: For each config-module in
# `<prefix>/<name>/<path-to-module>` a forwarding config-module will be
# generated in `<prefix>/<path-to-module>` which includes the actual config-
# module.
#

function(add_pkg NAME)
  # test list compatibility
  set(s ${NAME})
  list(LENGTH s l)
  if(NOT l EQUAL 1)
    message(FATAL_ERROR "'${NAME}' is an invalid name for a package")
  endif()
  if(NOT EXISTS "${CB_OUT_FILE_TO_APPEND}")
    message(FATAL_ERROR "Internal error, the specified temporary file "
        "CB_OUT_FILE_TO_APPEND = \"${CB_OUT_FILE_TO_APPEND}\" "
        "does not exist")
  endif()
  if(IS_DIRECTORY "${CB_OUT_FILE_TO_APPEND}")
    message(FATAL_ERROR "Internal error, the specified temporary file "
        "CB_OUT_FILE_TO_APPEND = \"${CB_OUT_FILE_TO_APPEND}\" "
        "is a directory")
  endif()
  file(APPEND "${CB_OUT_FILE_TO_APPEND}" "${NAME};${ARGN}\n")
endfunction()
