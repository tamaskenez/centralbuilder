set(SCM https://scm.adasworks.com/r)
set(TPS ${SCM}/thirdparty/src)

add_pkg(ZLIB GIT_REPOSITORY ${TPS}/zlib CMAKE_ARGS "-DVARIABLE=contains space")
add_pkg(PNG GIT_REPOSITORY ${TPS}/png DEPENDS ZLIB)
