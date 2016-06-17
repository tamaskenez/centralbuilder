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
      "error. Please check the file `${INSTALL_PREFIX}/centralbuilder"
      "/build_log.txt`.")
  endmacro()
endif()

function(log_command)
  math(EXPR argc_minus_1 "${ARGC}-1")
  set(s "")
  foreach(i RANGE 0 ${argc_minus_1})
    set(a "${ARGV${i}}")
    if(a MATCHES "[ ;]")
      set(s "${s} \"${a}\"")
    else()
      set(s "${s} ${a}")
    endif()
  endforeach()
  message(STATUS "[centralbuild] ${s}")
endfunction()

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

set(report_dir "${INSTALL_PREFIX}/centralbuilder")

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
    -UCB_*
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
      -UCB_*
      "-DCB_ADD_PKG_CMAKE=${CMAKE_CURRENT_LIST_DIR}/detail/AddPkg.cmake"
      "-DCB_PKG_REGISTRY_FILE_IN=${pkg_registry_file_in}"
      "-DCB_OUT_FILE_TO_APPEND=${out_file_to_append}"
      ${tp_source_dir}
    WORKING_DIRECTORY ${tp_binary_dir}
    RESULT_VARIABLE result
  )
endfunction()

# sort+unique a list which may contain nested lists
macro(list_sort_unique_keep_nested_lists listname)
    string(REPLACE "\;" "\t" ${listname} "${${listname}}")
    list(SORT ${listname})
    list(REMOVE_DUPLICATES ${listname})
    string(REPLACE "\t" "\;" ${listname} "${${listname}}")
endmacro()

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
      file(APPEND "${pkg_requests_file}" "${line}\n")
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
set(hijack_modules_dir "${INSTALL_PREFIX}/centralbuilder_hijack_modules")
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

set(log_file "${report_dir}/build_log.txt")
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

# list of packages we've built so far in the loop
set(packages_built_now "")
# list of packages we've failed to built in the loop
set(packages_failed_to_build_now "")
set(package_names_processed "")

foreach(pkg_request IN LISTS PKG_REQUESTS)
  list(GET pkg_request 0 pkg_name)
  # Remove package name with this hack
  # We could treat pkg_request as a list and remove first item but
  # that does not preserve nested lists
  string(REGEX REPLACE "!_BEGIN_![^;]+;" "" pkg_args "!_BEGIN_!${pkg_request}")

  message(STATUS "****************************************************************")
  message(STATUS "* Package: ${pkg_name}:")
  message(STATUS "* \t${pkg_args}")
  message(STATUS "****************************************************************")

  list(APPEND package_names_processed "${pkg_name}")
  # we'll remove this after successful build or
  # if we find out that this package does not need to
  # be rebuilt
  list(APPEND packages_failed_to_build_now "${pkg_name}")

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
  set(PACKAGE_INSTALL_PREFIX_${pkg_name} "${pkg_install_prefix}")
  set(PACKAGE_DEPENDS_${pkg_name} "${PKG_DEPENDS}")
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

  string(REGEX REPLACE "-D;([^;]*)" "-D\\1" gca "${GLOBAL_CMAKE_ARGS}")
  string(REGEX REPLACE "-D;([^;]*)" "-D\\1" pca "${PKG_CMAKE_ARGS}")

  set(actual_cmake_args "")
  set(actual_cmake_prefix_path "${pkg_prefix_path}")
  set(actual_cmake_module_path "${pkg_module_path}")
  foreach(ca IN LISTS gca pca)
    if(ca MATCHES "^-DCMAKE_INSTALL_PREFIX=(.*)$")
      log_error("GLOBAL_CMAKE_ARGS or CMAKE_ARGS for package \"${pkg_name}\" defines CMAKE_INSTALL_PREFIX which should not be defined at those places.")
    elseif(ca MATCHES "^-DCMAKE_PREFIX_PATH=(.*)$")
      set(actual_cmake_prefix_path "${CMAKE_MATCH_1};${actual_cmake_prefix_path}")
    elseif(ca MATCHES "^-DCMAKE_MODULE_PATH=(.*)$")
      set(actual_cmake_module_path "${CMAKE_MATCH_1};${actual_cmake_module_path}")
    else()
      # We need two levels of escaping here
      # The first level needed inside actual_cmake_args which is a list on it own
      # The second level will be consumed when actual_cmake_args will be expanded
      # as the command-line of execute_process()
      string(REPLACE ";" "\\\;" ca "${ca}")
      list(APPEND actual_cmake_args "${ca}")
    endif()
  endforeach()

  string(REPLACE ";" "\;" actual_cmake_prefix_path "${actual_cmake_prefix_path}")
  string(REPLACE ";" "\;" actual_cmake_module_path "${actual_cmake_module_path}")

  # determine the actual commit without cloning
  if(PKG_GIT_TAG)
    set(ref "${PKG_GIT_TAG}")
  else()
    set(ref "HEAD")
  endif()

  set(result "")
  foreach(retries 1 2 3 4 5)
    if(result)
      message(STATUS "'git ls-remote ${PKG_GIT_URL} ${ref}' failed")
      math(EXPR sleep_sec "${retries}")
      message(STATUS "Sleeping ${sleep_sec} secs and retrying...")
      execute_process(COMMAND ${CMAKE_COMMAND}
        -E sleep ${sleep_sec})
    endif()

    execute_process(COMMAND ${GIT_EXECUTABLE}
        ls-remote --exit-code "${PKG_GIT_URL}" "${ref}"
      RESULT_VARIABLE result
      OUTPUT_VARIABLE ls_remote_output
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT result OR result EQUAL 2)
      break()
    endif()
  endforeach()

  if(result EQUAL 2 AND PKG_GIT_TAG MATCHES "^[0-9a-fA-F]+$")
    set(result 0)
    set(pkg_rev_parse_head 0) # 0 means it's possibly an SHA
    message(STATUS "${pkg_name}: git ls-remote ${ref} returned no-matching-ref: assuming it's a valid SHA.")
  elseif(result)
    log_error("'git ls-remote ${PKG_GIT_URL} ${ref}' failed")
    continue()
  else()
    string(REGEX MATCH "[0-9a-fA-F]+" pkg_rev_parse_head "${ls_remote_output}")
    if(NOT pkg_rev_parse_head)
      log_error("Failed to parse result of 'git ls-remote ${PKG_GIT_URL} ${ref}' which was '${ls_remote_output}'")
      continue()
    endif()
    message(STATUS "${pkg_name}: git ls-remote ${ref} returned ${pkg_rev_parse_head}")
  endif()


  foreach(config IN LISTS CONFIGS)
    message(STATUS "---------------- CONFIG: ${config} ----------------")
    # The next section in the while() will be executed first without actually
    # having cloned out the repository.
    # If it turns out that the repository is going to be built
    # we clone the repo and re-run this section because the
    # repository may have changed in the meantime so the current SHA
    # must be evaluated again.
    set(pkg_cloned 0)
    foreach(lazy_clone_phase 1 2 3)
      if(lazy_clone_phase EQUAL 3)
        set(log_error_result "Internal error: lazy-clone loop executed three times.")
        break()
      endif()
      # current args_for_stamp
      set(args_for_stamp "${actual_cmake_args};SHA=${pkg_rev_parse_head}")
      # make canonical arg list
      string(REGEX REPLACE "(^|;)-([CDUGTA]);" "\\1-\\2" args_for_stamp "${args_for_stamp}")
      if(args_for_stamp MATCHES "(^|;)-DCMAKE_TOOLCHAIN_FILE=([^;]+)")
        set(ctf "${CMAKE_MATCH_2}")
        if(EXISTS "${ctf}")
          file(MD5 "${ctf}" md5)
          string(REPLACE "-DCMAKE_TOOLCHAIN_FILE=${ctf}"
            "-DCMAKE_TOOLCHAIN_FILE=${md5}" args_for_stamp "${args_for_stamp}")
        endif()
      endif()
      list_sort_unique_keep_nested_lists(args_for_stamp)
      set(stamp_filename "${report_dir}/stamps/${pkg_name}-${config}-installed.txt")

      # compare to existing stamp file
      set(same_args_as_already_installed 0)
      if(EXISTS "${stamp_filename}")
        file(READ "${stamp_filename}" installed_stamp_content)
        if(installed_stamp_content STREQUAL args_for_stamp)
          set(same_args_as_already_installed 1)
        endif()
      else()
        set(installed_stamp_content "")
      endif()

      set(fail_this_build_reason "")
      foreach(d IN LISTS PKG_DEPENDS)
        if(";${package_names_processed};" MATCHES ";${d};")
          # fail build if a dependency failed to build now
          if(";${packages_failed_to_build_now};" MATCHES ";${d};")
            set(fail_this_build_reason "dependency '${d}' failed.")
            break()
          endif()
          if(same_args_as_already_installed)
            # Force rebuild if a dependency of this has been built
            # after this package.
            set(dep_stamp_filename "${report_dir}/stamps/${d}-${config}-installed.txt")
            if(EXISTS "${dep_stamp_filename}")
              if("${dep_stamp_filename}" IS_NEWER_THAN "${stamp_filename}")
                set(same_args_as_already_installed 0)
                message(STATUS "Rebuilding '${pkg_name}' because '${d}' is newer.")
                file(TIMESTAMP "${dep_stamp_filename}" dep_timestamp)
                file(TIMESTAMP "${stamp_filename}" pkg_timestamp)
                message(STATUS "${dep_stamp_filename}: ${dep_timestamp}")
                message(STATUS "${stamp_filename}: ${pkg_timestamp}")
              endif()
            else()
              set(fail_this_build_reason "install-timestamp of dependency '${d}' not found")
              break()
            endif()
          endif()
        else()
          message(STATUS "Dependency ${d} is not specified in the current package registries.")
        endif()
      endforeach()

      if(fail_this_build_reason)
        set(log_error_result "${fail_this_build_reason}")
        break()
      else()
        set(log_error_result "")
      endif()

      if(same_args_as_already_installed OR pkg_cloned)
        break() # nothing to do
      else()
        # clone if there's no git in the clone dir
        if(NOT EXISTS "${pkg_clone_dir}/.git")
          if(pkg_rev_parse_head STREQUAL "0") # PKG_GIT_TAG is probably an SHA
            set(git_options "")
          else()
            set(git_options --depth 1)
            if(PKG_GIT_TAG)
              list(APPEND git_options --branch ${PKG_GIT_TAG})
            endif()
          endif()
          execute_process(
            COMMAND ${GIT_EXECUTABLE} clone --recursive ${git_options}
              ${PKG_GIT_URL} ${pkg_clone_dir}
            RESULT_VARIABLE result)
          if(result)
            set(log_error_result "git clone failed.")
            break()
          endif()

          if(pkg_rev_parse_head STREQUAL "0") # PKG_GIT_TAG is probably an SHA
            execute_process(
              COMMAND ${GIT_EXECUTABLE} checkout ${PKG_GIT_TAG}
              WORKING_DIRECTORY ${pkg_clone_dir}
              RESULT_VARIABLE result)
            if(result)
              set(log_error_result "git checkout failed after successful clone")
              # remove cloned dir otherwise in next time we would leave it
              # as it is (at HEAD commit) and build at that commit
              file(REMOVE_RECURSE ${pkg_clone_dir})
              break()
            endif()
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
          set(log_error_result "git rev-parse HEAD failed")
          break()
        endif()

        set(pkg_cloned 1)
        # loop executes once more and re-evalutes the variables
        # that depend on pkg_rev_parse_head
      endif()
    endforeach() # foreach(lazy_clone_phase)

    if(log_error_result)
      log_error("${log_error_result}")
      continue()
    endif()

    # this `if` would be more readable with `continue`
    # but older CMake has no `continue`
    if(same_args_as_already_installed)
      message(STATUS "${pkg_name}-${config} has already been installed with "
        "the same CMAKE_ARGS and SHA, skipping build. Stamp content: "
        "${args_for_stamp}")
    else()
      # compute all dependencies (recursively)
      set(deps_to_resolve "${PKG_DEPENDS}")
      set(deps_resolved "")
      while(deps_to_resolve)
        list(GET deps_to_resolve -1 d)
        list(REMOVE_AT deps_to_resolve -1)
        list(APPEND deps_resolved "${d}")
        if(PACKAGE_DEPENDS_${d})
          foreach(dd IN LISTS PACKAGE_DEPENDS_${d})
            list(FIND deps_resolved "${dd}" dd_idx)
            if(dd_idx EQUAL -1)
              list(APPEND deps_to_resolve "${dd}")
            endif()
          endforeach()
        endif()
      endwhile()
      set(deps_install_prefixes "")
      if(deps_resolved)
        message(STATUS "List of recursive dependencies: ")
        cmake_print_variables(deps_resolved)
        foreach(d IN LISTS deps_resolved)
          if(PACKAGE_INSTALL_PREFIX_${d} AND NOT pkg_install_prefix STREQUAL PACKAGE_INSTALL_PREFIX_${d})
            list(APPEND deps_install_prefixes "${PACKAGE_INSTALL_PREFIX_${d}}")
          endif()
        endforeach()
      endif()
      list(REMOVE_DUPLICATES deps_install_prefixes)
      if(deps_install_prefixes)
        message(STATUS "This package needs may need to access libraries from "
          "the following additional install prefixes:")
        cmake_print_variables(deps_install_prefixes)
      else()
        message(STATUS "This package will be built into the same install prefix as "
          "its dependencies")
      endif()

      # compute RPATH_LINK
      set(RPATH_LINK "")
      foreach(dip IN LISTS deps_install_prefixes)
        list(APPEND RPATH_LINK "${dip}/lib")
      endforeach()
      string(REPLACE ";" ":" RPATH_LINK "${RPATH_LINK}")
      if(RPATH_LINK)
        cmake_print_variables(RPATH_LINK)
      endif()

      # display reason of build/rebuild
      if(installed_stamp_content)
        message(STATUS "Previous build pars: ${installed_stamp_content}")
        message(STATUS "Current build pars: ${args_for_stamp}")
        message(STATUS "Pars are different, rebuilding")
      else()
        message(STATUS "There is no previous build, building now for the first time.")
      endif()

      set(ENV_LD_LIBRARY_PATH_SAVED "$ENV{LD_LIBRARY_PATH}")
      set(ENV_DYLD_LIBRARY_PATH_SAVED "$ENV{DYLD_LIBRARY_PATH}")
      set(ENV{LD_LIBRARY_PATH} "${RPATH_LINK}:$ENV{LD_LIBRARY_PATH}")
      set(ENV{DYLD_LIBRARY_PATH} "${RPATH_LINK}:$ENV{DYLD_LIBRARY_PATH}")
      message(STATUS "\$ENV{LD_LIBRARY_PATH}: $ENV{LD_LIBRARY_PATH}")
      message(STATUS "\$ENV{DYLD_LIBRARY_PATH}: $ENV{DYLD_LIBRARY_PATH}")

      # configure
      file(MAKE_DIRECTORY "${pkg_binary_dir}")
      log_command(cd "${pkg_binary_dir}")
      set(command_args
          -DCMAKE_INSTALL_PREFIX=${pkg_install_prefix}
          "-DCMAKE_PREFIX_PATH=${actual_cmake_prefix_path}"
          "-DCMAKE_MODULE_PATH=${actual_cmake_module_path}"
          ${actual_cmake_args}
          -DCMAKE_BUILD_TYPE=${config}
          ${pkg_source_dir}
      )
      log_command(cmake ${command_args})
      execute_process(
        COMMAND ${CMAKE_COMMAND}
          ${command_args}
        WORKING_DIRECTORY ${pkg_binary_dir}
        RESULT_VARIABLE result
      )
      if(result)
        log_error("configure failed.")
        continue()
      endif()

      # build
      set(command_args
          --build ${pkg_binary_dir}
          --config ${config}
          --clean-first)
      log_command(cmake ${command_args})
      execute_process(
        COMMAND ${CMAKE_COMMAND} ${command_args}
        RESULT_VARIABLE result
      )
      if(result)
        set(ENV{LD_LIBRARY_PATH} "${ENV_LD_LIBRARY_PATH_SAVED}")
        set(ENV{DYLD_LIBRARY_PATH} "${ENV_DYLD_LIBRARY_PATH_SAVED}")
        log_error("build failed.")
        continue()
      endif()

      # separate install to help debugging
      set(command_args
          --build ${pkg_binary_dir}
          --config ${config}
          --target install)
      log_command(cmake ${command_args})
      execute_process(
        COMMAND ${CMAKE_COMMAND} ${command_args}
        RESULT_VARIABLE result
      )

      set(ENV{LD_LIBRARY_PATH} "${ENV_LD_LIBRARY_PATH_SAVED}")
      set(ENV{DYLD_LIBRARY_PATH} "${ENV_DYLD_LIBRARY_PATH_SAVED}")

      if(result)
        log_error("install failed.")
        continue()
      endif()

      # successful install, write out install stamp
      file(WRITE "${stamp_filename}" "${args_for_stamp}")

      # packages_built_now will contain one pkg_name multiple times
      # (one for each config) but that's fine
      list(APPEND packages_built_now "${pkg_name}")
    endif() # if NOT same args as already installed
  endforeach()

  # replace original GIT_TAG (if any) with current one
  string(REGEX REPLACE ";GIT_TAG;[^;]*" "" pkg_resolved "${pkg_request}")
  file(APPEND ${pkg_resolved_file} "${pkg_resolved};GIT_TAG;${pkg_rev_parse_head}\n")

  if(";${failed_pkgs};" MATCHES ";${pkg_name};")
    file(APPEND "${log_file}" "[ERROR] Failed package: ${pkg_name}\n")
  else()
    list(REMOVE_ITEM packages_failed_to_build_now "${pkg_name}")
    if(PKG_NEST AND ";${packages_built_now};" MATCHES ";${pkg_name};")
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
        endif() # if match found
      endforeach() # for each config module
    endif() # if NEST
  endif() # else of if pkg failed
endforeach() # for each pkg

execute_process(
  COMMAND ${CMAKE_COMMAND}
    ${GLOBAL_CMAKE_ARGS}
    -UCB_*
    "-DCB_FIND_PACKAGE_REPORT_FILE=${report_dir}/find_package_report.txt"
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
    "information. ${report_dir}/build_log.txt contains the log of errors and list "
    "of failed packages.")
else()
  message(STATUS "Successful build. See ${report_dir} for more "
    "information. ${report_dir}/find_package_report.txt contains the log of test "
    "find_package commands for each package.")
endif()
