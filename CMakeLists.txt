cmake_minimum_required(VERSION 2.8.7)
project(CentralBuilder)

include(ExternalProject)

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
    file(DOWNLOAD "${pr}" "${tmpfile}")
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

foreach(pkg_name IN LISTS PKG_NAMES)
  message(STATUS "Package: ${pkg_name}:")
  message(STATUS "\t${PKG_ARGS_${pkg_name}}")
  ExternalProject_Add(
    ${pkg_name}
    ${PKG_ARGS_${pkg_name}}
    CMAKE_ARGS ${PKG_CMAKE_ARGS}
      -DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}
      -DCMAKE_PREFIX_PATH=${CMAKE_INSTALL_PREFIX}
      -DCMAKE_BUILD_TYPE=$<CONFIGURATION>
      -DCMAKE_MODULE_PATH=${hijack_modules_dir}
  )
endforeach()
