cmake_minimum_required(VERSION 2.8.7)
project(CentralBuilder)

include(CMakePrintHelpers)

include(AddPkg.cmake)

if(NOT PKG_CMAKE_ARGS)
  message(STATUS "The PKG_CMAKE_ARGS variable is empty.")
  message(STATUS "You can set global cmake options in the PKG_CMAKE_ARGS "
    "variable. These options will be used for the `cmake` command-line "
    "for all the packages so this is the place to specify things like "
    "the generator (-G) and similar options (-A, -T, toolchain)")
else()
  message(STATUS "PKG_CMAKE_ARGS: ${PKG_CMAKE_ARGS}")
endif()

if(NOT PKG_REGISTRIES)
  message(FATAL_ERROR "Specify at least one package registry (URL or file)"
                      " in the PKG_REGISTRIES variable")
endif()

set(PKG_NAMES "" CACHE INTERNAL "" FORCE)
set(tmpfile ${CMAKE_CURRENT_BINARY_DIR}/pr.tmp)
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
    include("${tmpfile}")
  elseif(pr MATCHES "\\.txt")
    file(READ "${tmpfile}" prc)
    foreach(line IN LISTS prc)
      add_pkg(${line})
    endforeach()
  else()
    message(FATAL_ERROR "The package registry files must have either '.txt' "
      "or '.cmake' extension. In the txt files on each line you can specify "
      "one pkg's ExternalProject_Add args. In the .cmake file you specify "
      "the packages with add_pkg(..) commands (see AddPkg.cmake). You can "
      "also use any CMake command to implement some logic. For example you "
      "can set a variable to your SCM's root URL and use that URL in the "
      "add_pkg commands.")
  endif()
endforeach()

list(LENGTH PKG_NAMES num_pkgs)

message(STATUS "Loaded ${num_pkgs} packages.")

set(hijack_modules_dir ${CMAKE_CURRENT_BINARY_DIR}/hijack_modules)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/FindPackageTryConfigFirst.cmake
  ${hijack_modules_dir}/FindPackageTryConfigFirst.cmake
  COPYONLY)
foreach(pkg_name IN LISTS PKG_NAMES)
  if(EXISTS ${CMAKE_ROOT}/Modules/Find${pkg_name}.cmake)
    #write a hijack module
    file(WRITE "${hijack_modules_dir}/Find${pkg_name}.cmake"
      "include(FindPackageTryConfigFirst)\nfind_package_try_config_first()\n")
  endif()
endforeach()

set(report_dir "${CMAKE_INSTALL_PREFIX}/centralbuilder_report")
set(pkgs_in_file "${report_dir}/packages_request.txt")
file(WRITE ${pkgs_in_file} "")

find_package(Git QUIET REQUIRED)
execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  OUTPUT_STRIP_TRAILING_WHITESPACE
)
if(result)
  message(WARNING "Can't retrieve this repo's git commit with rev-parse HEAD")
  set(cb_commit "???")
else()
  set(cb_commit "${output}")
endif()

set(extproj_cmake "${CMAKE_ROOT}/Modules/ExternalProject.cmake")
set(patched_extproj_cmake "")
if(DEPTH1_PATCH AND EXISTS "${extproj_cmake}")
  file(READ "${extproj_cmake}" f)
  set(spc0 "[ \t\r\n]*")
  set(spc "[ \t\r\n]+")
  set(notspc "[^ \t\r\n]+")
  set(ep_regex "execute_process${spc0}\\(${spc0}COMMAND${spc}${notspc}[gG][iI][tT]${notspc}${spc}clone${spc}[^)]*\\)")
  string(REGEX MATCH  "${ep_regex}" ep_match "${f}")
  if(ep_match)
    string(REGEX REPLACE "${spc}clone${spc}" " clone --depth 1 " ep_patched_match "${ep_match}")
    string(REPLACE "\\" "\\\\" ep_patched_match "${ep_patched_match}")
    string(REGEX REPLACE "${ep_regex}" "${ep_patched_match}" patched_f "${f}")
    set(patched_extproj_cmake "${CMAKE_CURRENT_BINARY_DIR}/PatchedExternalProject.cmake")
    file(WRITE ${patched_extproj_cmake} "${patched_f}")
  endif()
endif()

if(patched_extproj_cmake)
  include(${patched_extproj_cmake})
  set(DEPTH1_PATH ON)
  message(STATUS "DEPTH1_PATCH was ON: ExternalProject.cmake has been patched to "
    "add '--depth 1' to the git clone command. Please note that this is a nasty "
    "hack and not guaranteed to work for all CMake versions.")
else()
  include(ExternalProject)
  set(DEPTH1_PATH OFF)
  message(STATUS "DEPTH1_PATCH was OFF: Using genuine ExternalProject.cmake. "
    "You can specify -DDEPTH1_PATCH to patch ExternalProject.cmake to add "
    "'--depth 1' to the git clone command. Please note that this is a nasty "
    "hack and not guaranteed to work for all CMake versions.")
endif()

string(TIMESTAMP ts)
string(TIMESTAMP ts_utc UTC)
file(WRITE "${report_dir}/env.txt"
  "TIMESTAMP: ${ts} = ${ts_utc}\n"
  "CMAKE_VERSION: ${CMAKE_VERSION}\n"
  "PKG_CMAKE_ARGS: ${PKG_CMAKE_ARGS}\n"
  "PKG_REGISTRIES: ${PKG_REGISTRIES}\n"
  "CENTRALBUILDER_GIT_COMMIT: ${cb_commit}\n"
  "HOST_SYSTEM: ${CMAKE_HOST_SYSTEM}\n"
  "HOST_SYSTEM_PROCESSOR: ${CMAKE_HOST_SYSTEM_PROCESSOR}\n"
  "DEPTH1_PATCH: ${DEPTH1_PATH}"
)

# extract CMAKE_GENERATOR
set(cmake_generator "")
set(PKG_CMAKE_ARGS ";${PKG_CMAKE_ARGS};")
set(gen_regex ";-G;?([^;]+);")
if(PKG_CMAKE_ARGS MATCHES "${gen_regex}")
  set(cmake_generator_option CMAKE_GENERATOR "${CMAKE_MATCH_1}")
  string(REGEX REPLACE "${gen_regex}" ";" PKG_CMAKE_ARGS "${PKG_CMAKE_ARGS}")
endif()
string(REGEX REPLACE "^;" "" PKG_CMAKE_ARGS "${PKG_CMAKE_ARGS}")
string(REGEX REPLACE ";$" "" PKG_CMAKE_ARGS "${PKG_CMAKE_ARGS}")

foreach(pkg_name IN LISTS PKG_NAMES)
  message(STATUS "Package: ${pkg_name}:")
  message(STATUS "\t${PKG_ARGS_${pkg_name}}")

  # replace \; in cmake args
  set(allargs "${PKG_ARGS_${pkg_name}}${PKG_CMAKE_ARGS}")
  set(sep "")
  foreach(s "!" "#" "%" "&" "," ":" "=" "@" "`" "~")
    if(NOT allargs MATCHES sep)
      set(sep "${s}")
      break()
    endif()
  endforeach()
  if(sep STREQUAL "")
    message(FATAL_ERROR "Can't find a good separator character for lists.")
  endif()
  string(REPLACE "\;" "${sep}" pkg_args "${PKG_ARGS_${pkg_name}}")
  string(REPLACE "\;" "${sep}" global_args "${PKG_CMAKE_ARGS}")

#  # extract SOURCE_DIR
#  set(source_dir_option "")
#  set(pkg_args ";${pkg_args};")
#  set(source_dir_regex ";SOURCE_DIR;([^;]+);")
#  if(pkg_args MATCHES "${source_dir_regex}")
#    set(source_dir "${CMAKE_MATCH_1}")
#    string(REGEX REPLACE "${source_dir_regex}" ";" pkg_args "${pkg_args}")
#    if(IS_ABSOLUTE "${SOURCE_DIR}")
#      message(FATAL_ERROR "Package ${pkg_name}: SOURCE_DIR must be a relative path")
#    endif()
#    set(download_dir ${pkg_name}-prefix/src/${pkg_name}) # the default download dir
#    set(source_dir_option DOWNLOAD_DIR ${download_dir} SOURCE_DIR ${download_dir}/${source_dir})
#  endif()
#  string(REGEX REPLACE "^;" "" pkg_args "${pkg_args}")
#  string(REGEX REPLACE ";$" "" pkg_args "${pkg_args}")

  ExternalProject_Add(
    ${pkg_name}
    ${pkg_args}
    CMAKE_ARGS ${global_args}
      -DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}
      -DCMAKE_PREFIX_PATH=${CMAKE_INSTALL_PREFIX}
      -DCMAKE_BUILD_TYPE=$<CONFIGURATION>
      -DCMAKE_MODULE_PATH=${hijack_modules_dir}
    LIST_SEPARATOR "${sep}"
    ${cmake_generator_option}
#    ${source_dir_option}
  )
  file(APPEND ${pkgs_in_file} "${pkg_name};${PKG_ARGS_${pkg_name}}\n")
endforeach()

add_custom_target(centralbuild_report ALL
  ${CMAKE_COMMAND}
    -DBINARY_DIR=${CMAKE_CURRENT_BINARY_DIR}
    -DREPORT_DIR=${report_dir}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/create_report.cmake
  COMMENT "Executing report.cmake"
  DEPENDS ${PKG_NAMES}
  VERBATIM
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
)
