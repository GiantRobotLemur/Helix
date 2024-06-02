# Development Environment

The system is being developed under Windows using either a free-standing build of
GNU g++ or MSVC/native GNU g++ and Google Test to run code natively in unit tests.

The build is orchestrated with CMake and can be created either to build a bootable
ISO image to run on a bare metal PC (more likely an emulator like Bochs), or a
native build of Google Test executables to allow logic to be developed with the
ease provided by a native development environment.

# Native Unit Test Environmnt

To configure a development environment which creates unit tests to run on the
host system you will need:

- CMake (3.22+)
- Google Test 1.12+
- A C++ compiler (MSVC or GNU g++)
- A build system, e.g.:
    - MSBuild (for MSVC)
    - GNU Make
    - Ninja

To configure a build tree, use the following:

```
# cmake -S Helix/Source/Boot -B build_tests -DCMAKE_PREFIX_PATH=<path to google test>
```

The command creates a folder `build_tests` which is out of source. You can
equally set the path to an in-source build folder with a prefix of `build` to
be ignored by git. The `<path to google test>` should point to the folder
containing the `include` and `lib` folders created by installing a build of
google test. If google test was installed as part of the local system, there
is no need for the `-DCMAKE_PREFIX_PATH=...` option.

To build using CMake:

```
cmake --build build_tests --parallel
```

Again, if the build folder `build_tests` should be the path to the folder referenced
when the configuration step was performed.

To execute the tests, run:

```
# cmake --test-dir build_tests --parallel
```

Equally you can create an MSVC solution with project files. I use in-source
builds so that Visual Studio can detect which files in the git repository have
changed. Either way, you can use the following:

```
cmake -S Helix/Source/Boot -B Helix/Source/Boot/build_tests \
    -DCMAKE_PREFIX_PATH=<path to google test> \
    -G "Microsoft Visual Studio 17 2022" -A x64
```

The `build_tests` folder will contain the .sln file which can be used to build
the source code and run unit tests which can be executed from the Test Explorer
panel.


## Target Development Environment

To build the code to run on a bare-metal PC, you will need a cross compiler
environment and the tools necessary to produce a bootable ISO 9660 image.

### Cross-Compilation Environment

Apologies to Mac/Linux users, the instructions below can probably be more
easily adapted to those platforms than they are to use on Windows. Windows
users might to better in WSL, but it makes development from MSVC more
difficult.

To create a cross compilation environment, download the [Cygwin](https://www.cygwin.com) installer.
Install the following packages:
- Devel
    - gcc (g++)
    - gdb
    - make
    - ninja
    - cmake
    - doxygen
    - texinfo
- Libs, Math
    - libgmp-devel
    - libmpc-devel
    - libmpfr-devel
- Utils
    - genisoimage
- Archive
    - unzip
    - zip
- Web
    - wget2

The following describes how to create the free-standing compiler in cygwin based on
the [OSDev](https://wiki.osdev.org/GCC_Cross-Compiler) article on the subject:

In the cygwin console, run:

```
# ld --version

# gcc --version
```

Note the versions printed.

Download [binutils](https://ftp.gnu.org/gnu/binutils/) source code with a version
compatible with that which is already installed, e.g. 2.42-1.

Download [gcc](https://gcc.gnu.org/) source code with a version compatible with
that which is already installed, e.g. 11.4.0-1.

Create a folder in your cygwin tree to install the cross compilers in:
`# mkdir /opt/cross`

Create a folder to build the cross compilation tools in:

`# mkdir ~/Resources`

Unpack the binutils and gcc source code into the new folder.

```
# cd ~/Resources
# export PREFIX=/opt/cross
# export PATH=$PREFIX/bin:$PATH
```

Create an inner shell for building tools for different target architectures:

```
# bash
# export TARGET=i686-elf
```

Configure and build binutils which contains the GNU linker and assembler.

```
# mkdir build-binutils-i686
# cd build-binutils-i686
# ./../binutils-x.y/configure --target=$TARGET --prefix="$PREFIX" \
        --with-sysroot --disable-nls --disable-werror
# make -j <processor count>
```

The -j option allows make to run multiple tasks in parallel. I recommend using a value equal to the number of processor cores on your machine. The build step might take a while, especially under Cygwin.

```
# make install
# cd ..
```

Make sure the assembler for the target architecture is in our build environment

`# which $TARGET-as`

Now configure the gcc build (which will take even longer):

```
# mkdir build-gcc-i686
# cd build-gcc-i686
# ./../gcc-x.y.z/configure --target=$TARGET --prefix=$PREFIX --disable-nls \
        --enable-languages=c,c++ --without-headers

# make all-gcc -j <processor count>
# make all-target-libgcc -j <processor count>
# make install-gcc
# make install-target-libgcc
# cd ..
# which $TARGET-gcc
# exit
```

If you are feeling bold then we can also create a cross compiler for x86_64-elf.

We need to reset our TARGET variable for the new architecture.

```
# bash
# export TARGET=x86_64-elf
# mkdir build-binutils-x64
```

Repeat steps to build binutils in the new folder.

`# cd ..`

The x64 architecture has some quirks with gcc, checkout the OS Dev article
[libgcc_without_red_zone](https://wiki.osdev.org/Libgcc_without_red_zone) to
know how to tweak the gcc build to support this option when compiling the kernel:

In folder gcc-x.y.z/gcc/config/i386, create a new file called `t-x86_64-elf`
Open it in your favourite editor and add the following lines:

```
MULTILIB_OPTIONS += mno-red-zone
MULTILIB_DIRNAMES += no-red-zone
```

Then register the file by editing gcc-x.y.z/gcc/config.gcc.

Open the file in your favourite editor.

Search the file for `x86_64-*-elf*)`

Before `tm_file` line add: `tmake_file="${tmake_file} i386/t-x86_64-elf"`

Save the file and cd to the `build-gcc-x64` folder. Build gcc using the steps
previously described.

Exit the shell used to build gcc to loose the TARGET environment variable, but
keep PREFIX and PATH.

`# exit`

The version of gcc/g++ we have built is freestanding rather than hosted. I.e.
it has little or no support libraries. However, some of the standard C/C++
headers are still available because they do not rely on pre-compiled code. See
[this](https://en.cppreference.com/w/cpp/freestanding) article on what is
supported by a free standing C++ compiler for further details.

In order to use these cross-compilers with CMake, you will either need to create
a toolchain file or to have installed the cross-compilers somewhere on the system
path, such as where the host compilers are installed. The two should be able to
co-exist side by side. If you wish to install the cross compilers alongside the
system compilers, use:

```
# which gcc
```

to determine the location and set that to the PREFIX environment variable when
configuring the cross compiler builds as described above. You may need to use
`sudo` when invoking the `make install*` steps to add the new compilation tools
to system folders.

Alternately, to create a toolchain file compatible with CMake, create a new
text file:

```
# i686-elf cross compiler CMake toolchain definition

set(arch "elf")
cmake_path(APPEND toolPath "${CMAKE_CURRENT_LIST_DIR}" "bin")

set(CMAKE_SYSTEM_NAME "Generic")
set(CMAKE_SYSTEM_PROCESSOR "i686")
set(CMAKE_SYSTEM_VERSION "Freestanding")

# Ensure we search for g++.exe under Cygwin.
if (CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    set(BINARY_EXT ".exe")
else()
    set(BINARY_EXT "")
endif()

cmake_path(APPEND CMAKE_ASM_COMPILER "${toolPath}"
           "${CMAKE_SYSTEM_PROCESSOR}-${arch}-gcc${BINARY_EXT}")

set(CMAKE_ASM_FLAGS_INIT "-ffreestanding -nostdlib -D__ASM__")

cmake_path(APPEND CMAKE_C_COMPILER "${toolPath}"
           "${CMAKE_SYSTEM_PROCESSOR}-${arch}-gcc${BINARY_EXT}")

set(CMAKE_C_FLAGS_INIT "-ffreestanding -nostdlib")

cmake_path(APPEND CMAKE_CXX_COMPILER "${toolPath}"
           "${CMAKE_SYSTEM_PROCESSOR}-${arch}-g++${BINARY_EXT}")

set(CMAKE_CXX_FLAGS_INIT "-ffreestanding -nostdlib")

set(CMAKE_C_COMPILER_WORKS 1)   # Skip Test because we are in a free-standing environment
set(CMAKE_CXX_COMPILER_WORKS 1) # Skip Test because we are in a free-standing environment

# Have compiler checks build a static library so that the CMake won't
# try to execute the results on the host platform.
set(CMAKE_TRY_COMPILE_TARGET_TYPE "STATIC_LIBRARY")
```

To create a toolchain file for an x86-64 cross compiler, set the
`CMAKE_SYSTEM_PROCESSOR` variable value to `x86_64` and the rest should work
itself out.

Note: If the cross compiler was created under Cygwin, the Cygwin DLL will need to
be somewhere on the path used when running the build tools. That might mean adding
the `cygwin64/bin` folder to the system path.

To use an x64 compiler/assembler to build 32-bit code, you may need to add the
`-m32` flag to `CMAKE_*_FLAGS_INIT` variable definitions.

### Creating a Runtime Environment

It's also worth building several different configurations of the IA32 emulator
[Bochs](https://bochs.sourceforge.io/) to test the project in. Under Windows and
Linux/X-Windows, Bochs can have an interactive GUI debugger.

Install Bochs from the binary package to create an installed folder structure,
then download source of the same version installed so that you can build
optimised variants. The more features you build into Bochs, the slower it
becomes and various useful features are not part of the binary distribution.

You can build Bochs using MSVC, but it needs to be configured under some kind
of POSIX shell, of which bash in cygwin is fine.

```
cd ~/Resources
unzip bochs-x.y
```

To configure Bochs to emulate an x86 system without the overhead of x64 emulation
edit `bochs-x.y/.conf.win64-vcpp` in your favourite editor.

Remove `--enable-x86-64` and `--enable-vmx=2` to disable 64-bit CPU emulation. To
configure the 64-bit MSVC build, run:

```
cd bochs-x.y
./.config.win64-vcpp
```

You can zip up the build tree using:

`# make win32_snap`

A zip file will appear in the parent folder, you can take it elsewhere to build
with MSVC at your leisure.

To add interactive debugging facilities, re-edit the `.config.win64-vcpp` file
add `--enable-debugger` and `--enable-debugger-gui`. Then re-configure, re-zip and
build elsewhere.

The Bochs executable is fairly self-contained. That means you can create various
versions of the .exe with different build settings, rename them and install them
along side the binary distribution under `C:\Program Files\Bochs-x.y`.
I suggest creating `bochs-i686.exe` and `bochs-i686-debugger.exe` at the very
least.

### Configuring Target Builds

To create a build which produces an ISO image, you will need to use the cross
compilers you have built, either by referencing a toolchain file or because
the build tools are part of the local system and can be found in the PATH.

```
# cmake -S Helix/Source/Boot -B build_target \
    -DCMAKE_TOOLCHAIN_FILE=<path to toolchain.cmake>
```

To build, use:

```
cmake --build build_target --target IsoImage --parallel
```

If bochs is installed, you can use a built-in of `IsoBoot` or `IsoDebug` to
build the ISO image and boot it in bochs, possibly with the interactive GUI
debugger.