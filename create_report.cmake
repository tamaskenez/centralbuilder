set(pkgs_in_file ${REPORT_DIR}/packages_request.txt)
set(pkgs_out_file ${REPORT_DIR}/packages_current.txt)

file(STRINGS ${pkgs_in_file} infile_lines)
file(WRITE ${pkgs_out_file} "")
find_package(Git REQUIRED QUIET)
foreach(line IN LISTS infile_lines)
  if(line MATCHES "GIT_REPOSITORY;")
    # determine the actual commit
    list(GET line 0 name)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
      WORKING_DIRECTORY ${BINARY_DIR}/${name}-prefix/src/${name}
      RESULT_VARIABLE result
      OUTPUT_VARIABLE output
      ERROR_VARIABLE error
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(NOT result EQUAL 0)
      file(APPEND ${pkgs_out_file}
        "message(FATAL_ERROR \"Package '${pkg_name}': Can't get current "
        "git commit, rev-parse HEAD returned '${result}', stdout: '${output}', "
        "stderr: '${error}'\n")
      set(output "???")
    endif()
    # replace original GIT_TAG (if any) with current one
    string(REGEX REPLACE ";GIT_TAG;[^;]*" "" line "${line}")
    set(line "${line};GIT_TAG;${output}")
  endif()
  file(APPEND ${pkgs_out_file} "${line}\n")
endforeach()
