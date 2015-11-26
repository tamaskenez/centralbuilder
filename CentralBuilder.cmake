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


# Helper functions #############################################################

# Replace each character in 'x' string
# with [c] or [cC] where c is the character
# Returns result in 'ans' variable
function(case_insensitive_regex x)
    string(REGEX REPLACE "." "\\0;" x "${x}")
    string(REGEX REPLACE ";$" "" x "${x}")
    set(ans "")
    foreach(c IN LISTS x)
        string(TOLOWER "${c}" c_lower)
        string(TOUPPER "${c}" c_upper)
        if(c_lower STREQUAL c_upper)
            set(ans "${ans}[${c_lower}]")
        else()
            set(ans "${ans}[${c_lower}${c_upper}]")
        endif()
    endforeach()
    set(ans "${ans}" PARENT_SCOPE)
endfunction()

# Add the `continue` macro printing a warning for older CMake's
if(CMAKE_VERSION VERSION_LESS 3.2)
  macro(continue)
    message(FATAL_ERROR "This CMake version (${CMAKE_VERSION}) does not "
      "support the `continue` command. Processing will be aborted at the first "
      "error. Please check the file `${INSTALL_PREFIX}/centralbuilder_report"
      "/log.txt`.")
  endmacro()
endif()

# Script starts here ###########################################################

include(CMakePrintHelpers)
include(CMakeParseArguments)
find_package(Git QUIET REQUIRED)

# Validate and parse arguments #################################################

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

# Report input settings ########################################################

message(STATUS "Running CentralBuilder.cmake")
message(STATUS "GLOBAL_CMAKE_ARGS: ${GLOBAL_CMAKE_ARGS}")
message(STATUS "PKG_REGISTRIES: ${PKG_REGISTRIES}")
message(STATUS "BINARY_DIR: ${BINARY_DIR}")
message(STATUS "INSTALL_PREFIX: ${INSTALL_PREFIX}")
message(STATUS "CONFIGS: ${CONFIGS}")

# Retrieve the CentralBuilder git commit (used only for reporting) #############
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


# Write out the first lines of centralbuilder_report ###########################

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

# Configure the test CMake project which runs with the same settings as the ####
# the packages' CMake projects.

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

# We are reading the package registry file specified for this script
# The processed requests should be appended to pkg_requests_file
set(pkg_requests_file "${report_dir}/packages_requested.txt")
file(WRITE ${pkg_requests_file} "")
set(pkg_resolved_file "${report_dir}/packages_resolved.txt")
file(WRITE ${pkg_resolved_file} "")

# Invokes the test project to load a *.cmake
# package registry file and by executing it
# append the result to a file.
# Input: ${pkg_registry_file_in} (from parent_scope)
# Output: ${out_file_to_append}
function(include_cmake_package_registry pkg_registry_file_in out_file_to_append)
  execute_process(
    COMMAND ${CMAKE_COMMAND}
      ${GLOBAL_CMAKE_ARGS}
      "-DCB_ADD_PKG_CMAKE=${CMAKE_CURRENT_LIST_DIR}/detail/AddPkg.cmake"
      "-DCB_PKG_REGISTRY_FILE_IN=${pkg_registry_file_in}"
      "-DCB_OUT_FILE_TO_APPEND=${out_file_to_append}"
      ${tp_source_dir}
    WORKING_DIRECTORY ${tp_binary_dir}
    RESULT_VARIABLE result
  )
endfunction()


set(tmpfile ${BINARY_DIR}/pkg_reg.tmp)
foreach(pr IN LISTS PKG_REGISTRIES)
  if(EXISTS "${pr}")
    # it's a local file
    message(STATUS "Loading ${pr}")
    configure_file("${pr}" "${tmpfile}" COPYONLY)
  else()
    # then it must be a remote file to download
    message(STATUS "Downloading ${pr}")
    file(DOWNLOAD "${pr}" "${tmpfile}" STATUS result)
    list(GET result 0 code)
    if(code)
      message(FATAL_ERROR "Download failed with ${result}.")
    endif()
  endif()
  # at this point the file pointed by pr is copied to `tmpfile`
  if(pr MATCHES "\\.cmake")
    include_cmake_package_registry("${tmpfile}" "${pkg_requests_file}")
  elseif(pr MATCHES "\\.txt")
    file(STRINGS "${tmpfile}" prc)
    foreach(line IN LISTS prc)
      file(APPEND "${pkg_requests_file}" "${line}")
    endforeach()
  else()
    message(FATAL_ERROR "The package registry files must have either '.txt' "
      "or '.cmake' extension.")
  endif()
endforeach()

# extract package names
set(PKG_NAMES "")
file(STRINGS "${pkg_requests_file}" PKG_REQUESTS)
foreach(l IN LISTS PKG_REQUESTS)
  if(NOT l STREQUAL "")
    # first item should be the package name
    list(GET l 0 name)
    list(APPEND PKG_NAMES "${name}")
  endif()
endforeach()

list(LENGTH PKG_NAMES num_pkgs)
message(STATUS "Loaded ${num_pkgs} packages.")

# generate hijack modules for these packages
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

set(log_file "${report_dir}/log.txt")
set(failed_pkgs "")
set(config "")
file(WRITE "${log_file}" "")
macro(log_error msg)
  if(config)
    file(APPEND ${log_file} "[ERROR] Package ${pkg_name} (${config}): ${msg}\n")
  else()
    file(APPEND ${log_file} "[ERROR] Package ${pkg_name}: ${msg}\n")
  endif()
  list(APPEND failed_pkgs "${pkg_name}")
endmacro()

foreach(pkg_request IN LISTS PKG_REQUESTS)
  list(GET pkg_request 0 pkg_name)
  # Remove package name with this hack
  # We could treat pkg_request as a list and remove first item but
  # that does not preserve nested lists
  string(REGEX REPLACE "!_BEGIN_![^;]+;" "" pkg_args "!_BEGIN_!${pkg_request}")

  message(STATUS "Package: ${pkg_name}:")
  message(STATUS "\t${pkg_args}")

  # Replace \; in pkg_cmake args to be able to parse it
  # First find a good substitute separator which is not used in the string
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

  set(options "NEST")
  set(oneValueArgs GIT_REPOSITORY GIT_URL GIT_TAG SOURCE_DIR)
  set(multiValueArgs DEPENDS CMAKE_ARGS)
  cmake_parse_arguments(PKG "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${pkg_args} )

  if(PKG_UNPARSED_ARGUMENTS)
    log_error("invalid arguments: ${PKG_UNPARSED_ARGUMENTS}")
    continue()
  endif()
  if(PKG_GIT_REPOSITORY)
    if(PKG_GIT_URL)
      log_error("both GIT_REPOSITORY and GIT_URL are specified")
      continue()
    else()
      set(PKG_GIT_URL "${PKG_GIT_REPOSITORY}")
    endif()
  else()
    if(NOT PKG_GIT_URL)
      log_error("either GIT_REPOSITORY or GIT_URL must be specified")
      continue()
    endif()
  endif()

  set(pkg_clone_dir "${BINARY_DIR}/clone/${pkg_name}")
  set(pkg_binary_dir "${BINARY_DIR}/build/${pkg_name}")
  if(PKG_NEST)
    set(pkg_install_prefix "${INSTALL_PREFIX}/${pkg_name}")
  else()
    set(pkg_install_prefix "${INSTALL_PREFIX}")
  endif()
  set(pkg_prefix_path "${INSTALL_PREFIX}")
  set(pkg_module_path "${hijack_modules_dir}")
  set(pkg_source_dir "${pkg_clone_dir}")
  if(PKG_SOURCE_DIR)
    if(IS_ABSOLUTE "${PKG_SOURCE_DIR}")
      log_error("SOURCE_DIR must be relative path")
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
      log_error("git clone failed.")
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
    log_error("git rev-parse HEAD failed")
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
      log_error("configure failed.")
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
      log_error("build failed.")
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
      log_error("install failed.")
      continue()
    endif()

  endforeach()

  if(PKG_NEST)
    # expose the config modules in ${INSTALL_PREFIX}/${pkg_name}
    # by creating config modules in ${INSTALL_PREFIX} which
    # contains a single "include()" line which loads the config module
    # from ${INSTALL_PREFIX}/${pkg_name}/...

    # collect all potential config-modules
    file(GLOB_RECURSE fns
      "${pkg_install_prefix}/*-config.cmake"
      "${pkg_install_prefix}/*Config.cmake"
      )

    foreach(fp IN LISTS fns)
      file(RELATIVE_PATH fprel "${pkg_install_prefix}" "${fp}")
      get_filename_component(fn "${fp}" NAME)
      string(REGEX MATCH "^(.*)(Config|-config)[.]cmake$" _ "${fn}")
      set(pn "${CMAKE_MATCH_1}") # package name, may be different from pkg_name
      get_filename_component(fprel_dir "${fprel}" PATH)
      case_insensitive_regex("${pn}")
      set(name_dot_regex "${ans}[^/]*")
      if(
        # <prefix>/
        fprel_dir STREQUAL ""
        # <prefix>/(cmake|CMake)/
        OR fprel_dir MATCHES "^(cmake|CMake)$"
        # <prefix>/<name>*/ and <prefix>/<name>*/(cmake|CMake)/
        OR fprel_dir MATCHES "^${name_dot_regex}(/(cmake|CMake))?$"
        # <prefix>/(lib/<arch>|lib|share)/cmake/<name>*/
        OR fprel_dir MATCHES "^(lib(/[^/]+)?|share)/cmake/${name_dot_regex}$"
        # <prefix>/(lib/<arch>|lib|share)/<name>*/
        OR fprel_dir MATCHES "^(lib(/[^/]+)?|share)/${name_dot_regex}$"
        # <prefix>/(lib/<arch>|lib|share)/<name>*/(cmake|CMake)/
        OR fprel_dir MATCHES "^(lib(/[^/]+)?|share)/${name_dot_regex}/(cmake|CMake)$"
      )
        set(forwarding_cm_path "${INSTALL_PREFIX}/${fprel}")
        get_filename_component(forwarding_cm_path_dir "${forwarding_cm_path}" PATH)
        file(RELATIVE_PATH forwarding_dir_to_cm "${forwarding_cm_path_dir}" "${fp}")
        file(WRITE "${forwarding_cm_path}"
          "include(\"\${CMAKE_CURRENT_LIST_DIR}/${forwarding_dir_to_cm}\")")
      endif()
    endforeach()
  endif()

  # replace original GIT_TAG (if any) with current one
  string(REGEX REPLACE ";GIT_TAG;[^;]*" "" pkg_resolved "${pkg_request}")
  file(APPEND ${pkg_resolved_file} "${pkg_resolved};GIT_TAG;${pkg_rev_parse_head}\n")

  if(failed_pkgs)
    file(APPEND "${log_file}" "[ERROR] Failed packages: ${failed_pkgs}\n")
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
  message(STATUS "Successful build. See ${report_dir} for more "
    "information. ${report_dir}/find_packages.txt contains the log of test "
    "find_package commands for each package.")
endif()
