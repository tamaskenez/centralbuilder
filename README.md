# CentralBuilder
Bianco CMake super-project that builds and install a list of packages (mostly
libraries) defined in a user file.


## Usage:

First you need to create a package registry file.

### Package Registry

This is a simple file to define the packages you want to build. There are two flavors of
it:

1. Simple text file (`*.txt`) each line defines one package
2. CMake file (*.cmake) where you can use any CMake commands. Plus define your
   packages with `add_pkg(...)` commands.

CentralBuilder builds your packages using CMake's built-in `ExternalProject`
module. So you need to specify a package with the parameters you would pass
to the `ExternalProject_Add` command. For detailed information see
[CMake docs - ExternalProject](https://cmake.org/cmake/help/latest/module/ExternalProject.html)

Let's see a simple package registry example, ZLIB and PNG defined in a `txt`
format, say `packages.txt`:

    ZLIB GIT_REPOSITORY https://github.com/hunter-packages/zlib.git CMAKE_ARGS -DBUILD_SHARED_LIBS=1
    PNG GIT_REPOSITORY git://git.code.sf.net/p/libpng/code DEPENDS ZLIB

The same in `cmake` format with some additional logic. Its filename can be
`packages.cmake`:

    add_pkg(ZLIB GIT_REPOSITORY https://github.com/hunter-packages/zlib.git
      CMAKE_ARGS -DBUILD_SHARED_LIBS=1)
    add_pkg(PNG GIT_REPOSITORY git://git.code.sf.net/p/libpng/code
      DEPENDS ZLIB)

### Notes about defining a package

- The package name must be the same name you use for `find_package` (use the
  same case, too).
- don't specify global options for the packages (see the following list) because
  they must be defined when you configure the CentralBuilder (see later)
  Such global options are:
  - CMAKE_BUILD_TYPE
  - CMAKE_GENERATOR, CMAKE_GENERATOR_TOOLSET, CMAKE_GENERATOR_PLATFORM
    (-G, -T, -A)
  - CMAKE_TOOLCHAIN  

### Building the packages

You need to configure the CentralBuilder project first, for example:

    cmake -H. -Bb -DCMAKE_INTALL_PREFIX=<...>
      -DPKG_REGISTRIES=<.../packages.txt> # or packages.cmake
      '-DPKG_CMAKE_ARGS=-G;Visual Studio 14 Win64`

The two interesting options are

- PKG_REGISTRIES is a list of URLs or file paths, your package registry files
- PKG_CMAKE_ARGS contains the global options for all packages

You also need to specify `-DCMAKE_BUILD_TYPE=Debug` (or another config) if
your generator for the super-project is not a multi-config one.

Note, that the super-project can be built with a different generator than the
packages. In the example above the super-project uses the default generator
which is usually `Unix Makefiles` (not multi-config) or `Visual Studio ...`
(multi-config) while the packages will be built with `Visual Studio 12 Win64`.

After you configured the super-project, build it:

    cmake --build b

If the super-project generator is multi-config, you need to add `--config`:

    cmake --build b --config Debug # or another config

Building the super-project will execute the ExternalProject custom targets
which download, build and install all the packages.


