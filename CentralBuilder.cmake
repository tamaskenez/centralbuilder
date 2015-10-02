# CentralBuilder cmake script
#
# Usage:
#
#     cmake [options] -P CentralBuilder.cmake
#
# Define the options by setting the following variables with -D, e.g.
#
#     cmake "-DPKG_CMAKE_ARGS=-G;Visual Studio 14" ... -P CentralBuilder.cmake
#
# Options:
#
# GLOBAL_CMAKE_ARGS: options passed to the cmake configure step of all packages
#   same list your could pass to ExternalProject_Add's CMAKE_ARGS option
#   Usually this list contains the cmake generator (-G) and toolchain options.
#
# PKG_REGISTRIES: list of file paths, (relative or absolute) or URLs of so
#   called package registry files which define what packages to build.
#   They're either simple text files with *.txt extension or cmake file
#   with *.cmake extension.
#   The text files define one package per line. Each line is similar to
#   what you would pass to ExternalProject_Add. Example
#
#       zlib;GIT_REPOSITORY;<url>;CMAKE_ARGS;-DBUILD_SHARED_LIBS=0
#
#   The same line in the cmake file should use the add_pkg command:
#
#       add_pkg(zlib GIT_REPOSITORY <url> CMAKE_ARGS -DBUILD_SHARED_LIBS=0)
#
#   The cmake file may use any other cmake commands and variables.
#
# BINARY_DIR: Build dir for the packages. Defaults to the current working
#   directory.
#
# INSTALL_PREFIX: CMAKE_INSTALL_PREFIX and CMAKE_PREFIX_PATH for the packages
#
# CONFIGS: list of configuration names like Debug;Release


include(CMakePrintHelpers)
include(CMakeParseArguments)
include(AddPkg.cmake)

if(NOT GLOBAL_CMAKE_ARGS)
  message(STATUS "The GLOBAL_CMAKE_ARGS variable is empty.")
  message(STATUS "You can set global cmake options in the GLOBAL_CMAKE_ARGS "
    "variable. These options will be used for the `cmake` command-line "
    "for all the packages so this is the place to specify things like "
    "the generator (-G) and similar options (-A, -T, toolchain)")
endif()

if(NOT PKG_REGISTRIES)
  message(FATAL_ERROR "Specify at least one package registry (URL or file)"
                      " in the PKG_REGISTRIES variable")
endif()

if(NOT BINARY_DIR)
  set(BINARY_DIR ${CMAKE_BINARY_DIR})
  message(STATUS "No BINARY_DIR specified, using current working directory.")
endif()

if(NOT INSTALL_PREFIX)
  message(FATAL_ERROR "No INSTALL_PREFIX specified.")
endif()

if(NOT CONFIGS)
  message(FATAL_ERROR "No CONFIGS specified.")
endif()

message(STATUS "Running CentraBuilder.cmake")
message(STATUS "GLOBAL_CMAKE_ARGS: ${GLOBAL_CMAKE_ARGS}")
message(STATUS "PKG_REGISTRIES: ${PKG_REGISTRIES}")
message(STATUS "BINARY_DIR: ${BINARY_DIR}")
message(STATUS "INSTALL_PREFIX: ${INSTALL_PREFIX}")
message(STATUS "CONFIGS: ${CONFIGS}")

function(include_package_registry filename)
  include("${filename}")
  set(PKG_NAMES "${PKG_NAMES}" PARENT_SCOPE)
  foreach(name IN LISTS PKG_NAMES)
    set(PKG_ARGS_${name} "${PKG_ARGS_${name}}" PARENT)
  endforeach()
endfunction()

set(PKG_NAMES "")
set(tmpfile ${BINARY_DIR}/pkg_reg.tmp)
foreach(pr IN LISTS PKG_REGISTRIES)
  if(EXISTS "${pr}")
    message(STATUS "Loading ${pr}")
    configure_file("${pr}" "${tmpfile}" COPYONLY)
  else()
    message(STATUS "Downloading ${pr}")
    file(DOWNLOAD "${pr}" "${tmpfile}" STATUS result)
    list(GET result 0 code)
    if(code)
      message(FATAL_ERROR "Download failed with ${result}.")
    endif()
  endif()
  if(pr MATCHES "\\.cmake")
    include_package_registry("${tmpfile}")
  elseif(pr MATCHES "\\.txt")
    file(READ "${tmpfile}" prc)
    foreach(line IN LISTS prc)
      add_pkg(${line})
    endforeach()
  else()
    message(FATAL_ERROR "The package registry files must have either '.txt' "
      "or '.cmake' extension.")
  endif()
endforeach()

list(LENGTH PKG_NAMES num_pkgs)

message(STATUS "Loaded ${num_pkgs} packages.")

set(hijack_modules_dir ${BINARY_DIR}/hijack_modules)
configure_file(${CMAKE_CURRENT_LIST_DIR}/FindPackageTryConfigFirst.cmake
  ${hijack_modules_dir}/FindPackageTryConfigFirst.cmake
  COPYONLY)
foreach(pkg_name IN LISTS PKG_NAMES)
  if(EXISTS ${CMAKE_ROOT}/Modules/Find${pkg_name}.cmake)
    #write a hijack module
    file(WRITE "${hijack_modules_dir}/Find${pkg_name}.cmake"
      "include(FindPackageTryConfigFirst)\nfind_package_try_config_first()\n")
  endif()
endforeach()

find_package(Git QUIET REQUIRED)
execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(result)
  message(WARNING "Can't retrieve this CentralBuilder repo's git commit with "
    "rev-parse HEAD")
  set(cb_commit "???")
else()
  set(cb_commit "${output}")
endif()

set(report_dir "${INSTALL_PREFIX}/centralbuilder_report")

string(TIMESTAMP ts)
string(TIMESTAMP ts_utc UTC)
file(WRITE "${report_dir}/env.txt"
  "TIMESTAMP: ${ts} = ${ts_utc}\n"
  "CMAKE_VERSION: ${CMAKE_VERSION}\n"
  "GLOBAL_CMAKE_ARGS: ${GLOBAL_CMAKE_ARGS}\n"
  "PKG_REGISTRIES: ${PKG_REGISTRIES}\n"
  "CENTRALBUILDER_GIT_COMMIT: ${cb_commit}\n"
  "HOST_SYSTEM: ${CMAKE_HOST_SYSTEM}\n"
  "HOST_SYSTEM_PROCESSOR: ${CMAKE_HOST_SYSTEM_PROCESSOR}\n"
)

set(pkgs_in_file "${report_dir}/packages_request.txt")
set(pkgs_out_file "${report_dir}/packages_current.txt")
file(WRITE ${pkgs_in_file} "")
file(WRITE ${pkgs_out_file} "")

foreach(pkg_name IN LISTS PKG_NAMES)
  set(pkg_args "${PKG_ARGS_${pkg_name}}")

  message(STATUS "Package: ${pkg_name}:")
  message(STATUS "\t${pkg_args}")

  # replace \; in pkg_cmake args to be able to parse it
  set(sep "")
  foreach(s "!" "#" "%" "&" "," ":" "=" "@" "`" "~")
    if(NOT pkg_args MATCHES sep)
      set(sep "${s}")
      break()
    endif()
  endforeach()
  if(sep STREQUAL "")
    message(FATAL_ERROR "Can't find a good separator character for lists.")
  endif()
  string(REPLACE "\;" "${sep}" pkg_args "${pkg_args}")

  set(options "")
  set(oneValueArgs GIT_REPOSITORY GIT_URL SOURCE_DIR)
  set(multiValueArgs DEPENDS CMAKE_ARGS)
  cmake_parse_arguments(PKG "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${pkg_args} )

  if(PKG_GIT_REPOSITORY)
    if(PKG_GIT_URL)
      message(FATAL_ERROR "Package ${pkg_name}: both GIT_REPOSITORY and GIT_URL are specified")
    else()
      set(PKG_GIT_URL "${PKG_GIT_REPOSITORY}")
    endif()
  else()
    if(NOT PKG_GIT_URL)
      message(FATAL_ERROR "Package ${pkg_name}: either GIT_REPOSITORY or GIT_URL must be specified")
    endif()
  endif()

  set(pkg_clone_dir "${BINARY_DIR}/clone/${pkg_name}")
  set(pkg_binary_dir "${BINARY_DIR}/build/${pkg_name}")
  set(pkg_install_prefix "${INSTALL_PREFIX}")
  set(pkg_prefix_path "${INSTALL_PREFIX}")
  set(pkg_module_path "${hijack_modules_dir}")
  set(pkg_source_dir "${cmake_clone_dir}")
  if(PKG_SOURCE_DIR)
    if(IS_ABSOLUTE "${PKG_SOURCE_DIR}")
      message(FATAL_ERROR "Package ${pkg_name}: SOURCE_DIR must be relative path")
    endif()
    set(pkg_source_dir "${pkg_source_dir}/${PKG_SOURCE_DIR}")
  endif()

  string(REPLACE "${sep}" "\;" PKG_CMAKE_ARGS "${PKG_CMAKE_ARGS}")


  # clone if there's no git in the clone dir
  if(NOT EXISTS "${pkg_clone_dir}/.git")
    set(branch_option "")
    if(ARG_GIT_TAG)
      set(branch_option --branch ${GIT_TAG})
    endif()
    execute_process(
      COMMAND ${GIT_EXECUTABLE} clone --depth 1 --recursive ${branch_option}
        ${ARG_GIT_URL} ${pkg_clone_dir}
      RESULT_VARIABLE result
    )
    if(result)
      message(FATAL_ERROR "Package ${pkg_name} git clone failed.")
    endif()
  endif()

  # determine the actual commit
  execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
    WORKING_DIRECTORY ${pkg_clone_dir}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE pkg_rev_parse_head
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  if(result)
    message(FATAL_ERROR "Package ${pkg_name} git rev-parse HEAD failed")
  endif()

  foreach(config IN LISTS CONFIGS)
    # configure
    file(MAKE_DIRECTORY "${pkg_binary_dir}")
    execute_process(
      COMMAND ${CMAKE_COMMAND}
        -DCMAKE_INSTALL_PREFIX=${pkg_install_prefix}
        "-DCMAKE_PREFIX_PATH=${pkg_prefix_path}"
        "-DCMAKE_MODULE_PATH=${pkg_module_path}"
        "${PKG_CMAKE_ARGS}"
        "${GLOBAL_CMAKE_ARGS}"
        -DCMAKE_BUILD_TYPE=${config}
        ${pkg_source_dir}
      WORKING_DIRECTORY ${pkg_binary_dir}
      RESULT_VARIABLE result
    )
    if(result)
      message(FATAL_ERROR "Package ${pkg_name}: configure failed.")
    endif()

    # build
    execute_process(
      COMMAND ${CMAKE_COMMAND}
        --build ${pkg_binary_dir}
        --config ${config}
      RESULT_VARIABLE result
    )
    if(result)
      message(FATAL_ERROR "Package ${pkg_name}: build failed.")
    endif()

    # separate install to help debugging
    execute_process(
      COMMAND ${CMAKE_COMMAND}
        --build ${pkg_binary_dir}
        --config ${config}
        --target install
      RESULT_VARIABLE result
    )
    if(result)
      message(FATAL_ERROR "Package ${pkg_name}: install failed.")
    endif()

  endforeach()

  set(line "${pkg_name};${PKG_ARGS_${pkg_name}}"
  file(APPEND ${pkgs_in_file} "${line}\n")

  # replace original GIT_TAG (if any) with current one
  string(REGEX REPLACE ";GIT_TAG;[^;]*" "" line "${line}")
  file(APPEND ${pkgs_out_file} "${line};GIT_TAG;${pkg_rev_parse_head}\n")

endforeach()
