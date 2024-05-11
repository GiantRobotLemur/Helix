# Helix - A Hobby Operating System
Helix is a work-in-progress hobby operating system.

While it has grandiose aspirations we'll start with a boot loader, kernel
and shell. The initial target is the x86 architecture with aspirations for x64
and then architecture independence. Most code is C++17 with a sprinkling of
assembly language where necessary.

There is another aspiration to create a programming language to compliment the
operating system in a similar manner to
[Oberon](https://en.wikipedia.org/wiki/Oberon_(programming_language))
and then re-write the kernel, drivers and shell in that language, but let's not
run before we can walk.

# Development Environment

The system is being developed under Windows using a free-standing build of
GNU g++, CMake and Google Test.

Apologies to Mac/Linux users, the instructions below can probably be more
easily adapted to those platforms than they are to use on Windows. Windows
users might to better in WSL, but it makes development from MSVC more
difficult.

To create a cross compilation environment, download the [Cygwin](https://www.cygwin.com) installer.
Install the following packages:
- Devel
    - gcc-g++
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
# ./../binutils-x.y/configure --target=$TARGET --prefix="$PREFIX"
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
# ./../gcc-x.y.z/configure --target=$TARGET --prefix=$PREFIX --disable-nls
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