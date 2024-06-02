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

## Progress

The project has progressed to a point where an ISO 9660 image file can be
created which contains a boot loader that ends up running 32-bit C++ code
built using a free-standing GNU g++ compiler.

That 32-bit code has access to some basic system information:
- The memory map
- Details of the boot device
- A function which will load sectors from the boot device

That code does little more than print 'Hello World' when the CD image is
booted, currently running in the Bochs emulator.

The aspiration is to write some utilities, like printf() and heap management
and start creating a useful runtime environment for a kernel, load the kernel
and driver binaries and hand over control to them.

## Links

[Building the repository](Docs/DevelopmentEnvironment.md)
