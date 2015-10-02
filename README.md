# CentralBuilder
Blank CMake super-project to clone, build and install a list of projects
defined in a text or cmake file.

We'll call those projects *packages* because CentralBuilder can be used to
create and maintain a simple local package-repository.

## Quick Start

Describe the packages you want to build in a text file:

    ZLIB;GIT_URL;https://github.com/hunter-packages/zlib.git;CMAKE_ARGS;-DBUILD_SHARED_LIBS=1
    PNG;GIT_URL;git://git.code.sf.net/p/libpng/code;DEPENDS;ZLIB

or in a cmake file:

    add_pkg(ZLIB GIT_URL https://github.com/hunter-packages/zlib.git
      CMAKE_ARGS -DBUILD_SHARED_LIBS=1)
    add_pkg(PNG GIT_URL git://git.code.sf.net/p/libpng/code DEPENDS ZLIB)

and launch `CentralBuilder.cmake`:

    cmake -DPKG_REGISTRIES=<path-to-your-file>
        -DBINARY_DIR=build -DINSTALL_PREFIX=install
        -DGLOBAL_CMAKE_ARGS=-GXcode "-DCONFIGS=Debug;Release"
        -P CentralBuilder.cmake

It clones, builds and installs the packages defined in your file.      

## Details:

### Script Parameters

`PKG_REGISTRIES` is a list of relative or absolute paths or URLs of `*.txt`
or `*.cmake` package registry files.
The text format defines one package per line, the arguments should be separated
by semicolons.
The cmake format uses the custom `add_pkg` function. Since you can also use
any cmake commands here use this format if you want to defined variables or
add additional logic.

`BINARY_DIR` is where the build directories and clones will reside.
The packages will be installed to 'INSTALL_DIR`. `BINARY_DIR` defaults
to the current directory.

`GLOBAL_CMAKE_ARGS` is a list of cmake-options which will be passed to each
package's `cmake` configure step. You can define here the CMake generator,
toolchain and the like (`-G`, `-A`, `-T`, `-DCMAKE_TOOLCHAIN`)

`CONFIGS` is the list of configurations to build, like `Debug;Release`

#### Argument Escaping

All the lists in the arguments must be semicolon-separated. You need to
escape the semicolon or quote the parameter. Examples:

    -DCONFIGS=Debug\;Release
    "-DCONFIGS=Debug;Release"

In case the an argument contains a list you need to escape it for CMake:

    "-DGLOBAL_CMAKE_ARGS=-G;Unix Makefiles;-DTESTVAR=one\;two"

### Package Registry Files

Both the text and cmake package registry use keywords borrowed from the
[ExternalProject](https://cmake.org/cmake/help/latest/module/ExternalProject.html)
module. Here follows the list of valid options you can use with `add_pkg` or
in the text file:

    add_pkg(<name> GIT_REPOSITORY|GIT_URL <url> [GIT_TAG <branch/tag/id>]
            [CMAKE_ARGS <args..>] [SOURCE_DIR <source-dir>]
            [DEPENDS <dependencies...>])

The first argument must be the name of the package. Let it be the same what
you pass to the `find_package` command because the packages will be tested
by `find_package` command after installation.

Use `GIT_REPOSITORY` or the shorter synonym `GIT_URL` to specify the URL of the
git repository. This is also mandatory.

Use `GIT_TAG` to checkout a given branch or tag or commit. For now the
git-clones will be done with `--depth 1` to save time and storage.

With `CMAKE_ARGS` you can list options to be passed to the cmake configuration
step of the package.

`SOURCE_DIR` is must be a relative path. Use this if the package's
`CMakeLists.txt` is in a subdirectory and not in the root of the repository.
(Note that one works a bit differently than by ExternalProject_Add)

You can list the dependencies of the package with the `DEPENDS` option. This
is ignored for now.

#### Escaping in the Package Registry Files

Use `\;` in the text files:

    ZLIB;GIT_URL=<url>;CMAKE_ARGS;-DTESTVAR=one\;two

and also in the cmake files:

    add_pkg(ZLIB GIT_URL <url> CMAKE_ARGS "-DTESTVAR=one\;two")

### Build Report

CentralBuilder creates various reports about the build in
`<INSTALL_DIR>/centralbuilder_report`. These are:

- `env.txt` lists the arguments of CentralBuilder.cmake and some information
  about the build environment
- `packages_request.txt` is union of the input package registry files in text
  format
- `packages_current.txt` is the same except it also describes actual
  git-commit-ids with the GIT_TAG keyword. Use this file to reproduce the same
  build of all packages later.
- `find_packages.txt` lists the result of `find_package` commands for the
  packages after installation.


### Further Details

- Don't call `add_pkg` from within a function
- CentralBuilder shadows the official CMake find-modules of
  the packages you are building. For example, if you're
  building `ZLIB` and `PNG` then `PNG`'s `find_package(ZLIB)` will find the
  config-module of `ZLIB` before it attempts `FindZLIB.cmake` from the
  CMake distribution. This works only for packages providing config-modules.
  Also, in your own project you need to solve this issue yourself.
- The stdout/stderr of the `cmake` commands CentralBuilder executes are
  sometimes intermixed with each other making it unreadable. This is a known
  bug of the CMake command `execute_process`.
