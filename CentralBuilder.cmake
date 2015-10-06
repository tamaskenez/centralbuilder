# CentralBuilder cmake script
#
# Usage:
#
#     cmake [options] -P CentralBuilder.cmake
#
# For detailed information see README.md
#
# Define the options by setting the following variables with -D, e.g.
#
#     cmake "-DPKG_CMAKE_ARGS=-G;Visual Studio 14" ... -P CentralBuilder.cmake
#
# Available options variables:
#
# - GLOBAL_CMAKE_ARGS
# - PKG_REGISTRIES
# - BINARY_DIR
# - INSTALL_PREFIX
# - CONFIGS

include(CMakePrintHelpers)
include(CMakeParseArguments)
include(${CMAKE_CURRENT_LIST_DIR}/detail/AddPkg.cmake)

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
else()
  set(prs "")
  foreach(pr IN LISTS PKG_REGISTRIES)
    get_filename_component(apr "${CMAKE_BINARY_DIR}/${pr}" ABSOLUTE)
    if(IS_ABSOLUTE "${pr}" AND EXISTS "${pr}")
      list(APPEND prs "${pr}")
    elseif(NOT IS_ABSOLUTE "${pr}" AND EXISTS "${apr}")
      list(APPEND prs "${apr}")
    else()
      list(APPEND prs "${pr}")
    endif()
  endforeach()
  set(PKG_REGISTRIES "${prs}")
endif()

if(NOT BINARY_DIR)
  set(BINARY_DIR ${CMAKE_BINARY_DIR})
  message(STATUS "No BINARY_DIR specified, using current working directory.")
elseif(NOT IS_ABSOLUTE "${BINARY_DIR}")
  get_filename_component(BINARY_DIR "${CMAKE_BINARY_DIR}/${BINARY_DIR}" ABSOLUTE)
endif()

if(NOT INSTALL_PREFIX)
  message(FATAL_ERROR "No INSTALL_PREFIX specified.")
elseif(NOT IS_ABSOLUTE "${INSTALL_PREFIX}")
  get_filename_component(INSTALL_PREFIX "${CMAKE_BINARY_DIR}/${INSTALL_PREFIX}" ABSOLUTE)
endif()

if(NOT CONFIGS)
  message(FATAL_ERROR "No CONFIGS specified.")
endif()

message(STATUS "Running CentralBuilder.cmake")
message(STATUS "GLOBAL_CMAKE_ARGS: ${GLOBAL_CMAKE_ARGS}")
message(STATUS "PKG_REGISTRIES: ${PKG_REGISTRIES}")
message(STATUS "BINARY_DIR: ${BINARY_DIR}")
message(STATUS "INSTALL_PREFIX: ${INSTALL_PREFIX}")
message(STATUS "CONFIGS: ${CONFIGS}")

function(include_package_registry filename)
  include("${filename}")
  set(PKG_NAMES "${PKG_NAMES}" PARENT_SCOPE)
  foreach(name IN LISTS PKG_NAMES)
    set(PKG_ARGS_${name} "${PKG_ARGS_${name}}" PARENT_SCOPE)
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
configure_file(${CMAKE_CURRENT_LIST_DIR}/detail/FindPackageTryConfigFirst.cmake
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
  WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
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
)

set(tp_source_dir ${BINARY_DIR}/centralbuilder-testproject)
set(tp_binary_dir ${tp_source_dir}/b)

configure_file(${CMAKE_CURRENT_LIST_DIR}/detail/ReportCMakeLists.txt
  ${tp_source_dir}/CMakeLists.txt COPYONLY)
file(MAKE_DIRECTORY ${tp_binary_dir})
execute_process(
  COMMAND ${CMAKE_COMMAND}
    ${GLOBAL_CMAKE_ARGS}
    "-DCB_ENV_REPORT_FILE=${report_dir}/env.txt"
    ${tp_source_dir}
  WORKING_DIRECTORY ${tp_binary_dir}
  RESULT_VARIABLE result
)
if(result)
  message(FATAL_ERROR "Configuring test project failed.")
endif()

set(pkgs_in_file "${report_dir}/packages_request.txt")
set(pkgs_out_file "${report_dir}/packages_current.txt")
file(WRITE ${pkgs_in_file} "")
file(WRITE ${pkgs_out_file} "")

set(log_file "${report_dir}/log.txt")
set(failed_pkgs "")
set(config "")
file(WRITE "${log_file}" "")
macro(log_error msg)
  if(config)
    file(APPEND ${log_file} "[ERROR] Package ${pkg_name} (${config}): ${msg}")
  else()
    file(APPEND ${log_file} "[ERROR] Package ${pkg_name}: ${msg}")
  endif()
  list(APPEND failed_pkgs "${pkg_name}")
endmacro()

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
    log_error("Can't find a good separator character for lists.")
    continue()
  endif()
  string(REPLACE "\;" "${sep}" pkg_args "${pkg_args}")

  set(options "")
  set(oneValueArgs GIT_REPOSITORY GIT_URL GIT_TAG SOURCE_DIR)
  set(multiValueArgs DEPENDS CMAKE_ARGS)
  cmake_parse_arguments(PKG "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${pkg_args} )

  if(PKG_UNPARSED_ARGUMENTS)
    log_error("Package ${pkg_name}: invalid arguments: ${PKG_UNPARSED_ARGUMENTS}")
    continue()
  endif()
  if(PKG_GIT_REPOSITORY)
    if(PKG_GIT_URL)
      log_error("Package ${pkg_name}: both GIT_REPOSITORY and GIT_URL are specified")
      continue()
    else()
      set(PKG_GIT_URL "${PKG_GIT_REPOSITORY}")
    endif()
  else()
    if(NOT PKG_GIT_URL)
      log_error("Package ${pkg_name}: either GIT_REPOSITORY or GIT_URL must be specified")
      continue()
    endif()
  endif()

  set(pkg_clone_dir "${BINARY_DIR}/clone/${pkg_name}")
  set(pkg_binary_dir "${BINARY_DIR}/build/${pkg_name}")
  set(pkg_install_prefix "${INSTALL_PREFIX}")
  set(pkg_prefix_path "${INSTALL_PREFIX}")
  set(pkg_module_path "${hijack_modules_dir}")
  set(pkg_source_dir "${pkg_clone_dir}")
  if(PKG_SOURCE_DIR)
    if(IS_ABSOLUTE "${PKG_SOURCE_DIR}")
      log_error("Package ${pkg_name}: SOURCE_DIR must be relative path")
      continue()
    endif()
    set(pkg_source_dir "${pkg_source_dir}/${PKG_SOURCE_DIR}")
  endif()

  string(REPLACE "${sep}" "\;" PKG_CMAKE_ARGS "${PKG_CMAKE_ARGS}")

  # clone if there's no git in the clone dir
  if(NOT EXISTS "${pkg_clone_dir}/.git")
    set(branch_option "")
    if(PKG_GIT_TAG)
      set(branch_option --branch ${PKG_GIT_TAG})
    endif()
    execute_process(
      COMMAND ${GIT_EXECUTABLE} clone --depth 1 --recursive ${branch_option}
        ${PKG_GIT_URL} ${pkg_clone_dir}
      RESULT_VARIABLE result
    )
    if(result)
      log_error("Package ${pkg_name}: git clone failed.")
      continue()
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
    log_error("Package ${pkg_name}: git rev-parse HEAD failed")
    continue()
  endif()

  foreach(config IN LISTS CONFIGS)
    # configure
    file(MAKE_DIRECTORY "${pkg_binary_dir}")
    execute_process(
      COMMAND ${CMAKE_COMMAND}
        -DCMAKE_INSTALL_PREFIX=${pkg_install_prefix}
        "-DCMAKE_PREFIX_PATH=${pkg_prefix_path}"
        "-DCMAKE_MODULE_PATH=${pkg_module_path}"
        ${PKG_CMAKE_ARGS}
        ${GLOBAL_CMAKE_ARGS}
        -DCMAKE_BUILD_TYPE=${config}
        ${pkg_source_dir}
      WORKING_DIRECTORY ${pkg_binary_dir}
      RESULT_VARIABLE result
    )
    if(result)
      log_error("Package ${pkg_name}: configure failed.")
      continue()
    endif()

    # build
    execute_process(
      COMMAND ${CMAKE_COMMAND}
        --build ${pkg_binary_dir}
        --config ${config}
      RESULT_VARIABLE result
    )
    if(result)
      log_error("Package ${pkg_name}: build failed.")
      continue()
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
      log_error("Package ${pkg_name}: install failed.")
      continue()
    endif()

  endforeach()

  set(line "${pkg_name};${PKG_ARGS_${pkg_name}}")
  file(APPEND ${pkgs_in_file} "${line}\n")

  # replace original GIT_TAG (if any) with current one
  string(REGEX REPLACE ";GIT_TAG;[^;]*" "" line "${line}")
  file(APPEND ${pkgs_out_file} "${line};GIT_TAG;${pkg_rev_parse_head}\n")

  if(failed_pkgs)
    file(APPEND "${log_file}" "[ERROR] Failed packages: ${failed_pkgs}")
  endif()

endforeach()

execute_process(
  COMMAND ${CMAKE_COMMAND}
    ${GLOBAL_CMAKE_ARGS}
    "-DCB_FIND_PACKAGE_REPORT_FILE=${report_dir}/find_packages.txt"
    "-DPKG_NAMES=${PKG_NAMES}"
    "-DCMAKE_PREFIX_PATH=${pkg_prefix_path}"
    "-DCMAKE_MODULE_PATH=${pkg_module_path}"
    ${tp_source_dir}
  WORKING_DIRECTORY ${tp_binary_dir}
  RESULT_VARIABLE result
)
if(result)
  message(WARNING "Configuring find-package test report failed.")
endif()

if(failed_pkgs)
  message(FATAL_ERROR "Build done with errors. See ${report_dir} for more "
    "information. ${report_dir}/log.txt contains the log of errors and list "
    "of failed packages.")
else()
  message(STATUS "Build done with success. See ${report_dir} for more "
    "information. ${report_dir}/find_packages.txt contains the log of test "
    "find_package commands for each package.")
endif()
