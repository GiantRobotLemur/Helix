//! @file Loader_x86.hpp
//! @brief The declaration of various symbols and definitions shared between the
//! 16-bit assembly language and 32-bit C++ portions of the loader.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2014-2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.

#ifndef _BOOT_LOADER_X86_H_
#define _BOOT_LOADER_X86_H_

/* Some utility macros */
#define MakeText1(x) # x
#define MakeText(x) MakeText1(x)

/* Segment Selectors */
#define GdtGdtAlias 0x08
#define GdtIdtAlias 0x10
#define GdtData16   0x18
#define GdtData32   0x20
#define GdtStack16  0x28
#define GdtCode16   0x30
#define GdtBiosCode 0x38
#define GdtCode32   0x40

#define Loader16BssSize 2048 // 2K for the IDT.
#define HardwareIrqBase 240
// #define Loader32Base 0x10000

//#define IsoSectorSize 2048
//#define IsoSectorSizePow2 11
//#define SystemPageSizePow2 12
//#define SystemPageSize (1 << SystemPageSizePow2)
//#define SystemPageDirSizePow2 22
//#define SystemPageDirSize (1 << SystemPageDirSizePow2)
#define Stack16Size 4096
#define Stack32Size 4096
#define Interop16EntryOffset 68
#define MinRamInMb 8

#define MemMapEntry_Size        20  /* sizeof(MemMapEntry) */
#define MemType_UsableRAM       1   /* See MemType::UsableRAM in Loader.h */
#define MemType_Reserved        2   /* See MemType::Reserved in Loader.h */
#define MemType_UsableAfterBoot 128 /* See MemType::UsableAfterBoot in Loader.h */

#define MinXmsInKb ((MinRamInMb - 1) * 1024)
#define MinRamInMbText MakeText(MinRamInMb)

// i386 ELF File format values.
#define ElfMagic 0x464C457F

// Define entities which aren't compatible with assembly language.
#ifndef __ASM__

#include <stdint.h>

/*! @brief A structure used to pass registers between 16/32 bit code */
struct Interop16Regs
{
    uint32_t EAX;   // +0
    uint32_t EBX;   // +4
    uint32_t ECX;   // +8
    uint32_t EDX;   // +12
    uint32_t ESI;   // +16
    uint32_t EDI;   // +20
    uint32_t EBP;   // +24
    uint16_t DS;    // +26
    uint16_t ES;    // +28
    uint32_t EFlags;// +32
    // 36-bytes total.
};

struct BootMemoryInfo
{
    uint16_t BaseParagraph;
    uint16_t ParagraphCount;
    uint32_t Flags;
};

struct Loader16Env
{
    uint8_t BiosBootDriveId;
    uint8_t BootMemCount;
    uint16_t Reserved;
    BootMemoryInfo MemInfo[1];
};

//! @brief A structure appearing at the top of the 16-bit loader stub.
struct Loader16Environment
{
    //! @brief The segment address of the 16-bit stack.
    uint16_t Stack16Segment;
    uint16_t Reserved1;

    //! @brief The segment address of the 16-bit code and data.
    uint16_t Loader16Segment;
    uint16_t Reserved2;

    // Fields added by genisoimage using the -boot-info-table.

    //! @brief The sector of the primary volume descriptor on the boot CD.
    uint32_t PrimaryVolumeDescriptorSector;

    //! @brief The sector of the loader on the boot CD.
    uint32_t BootFileSector;

    //! @brief The size of the boot loader, in bytes.
    uint32_t BootFileSize;

    // Pad upto 64 bytes.
    uint32_t Reserved3[11];

    // Further 16-bit environment fields.
    //! @brief The size of the 16-bit loader COM file.
    uint32_t Loader16Size;

    //! @brief The size of the 32-bit loader EXE file.
    uint32_t Loader32Size;

    //! @brief The offset into the 16-bit code of the interop entry point.
    uint16_t Interop16Offset;

    //! @brief The segment address the loader was originally placed at.
    uint16_t OriginalLoadSegment;

    //! @brief The INT13 ID of the boot device.
    uint8_t BootDeviceId;
    uint8_t Reserved4[3];

    //! @brief A pointer to the 32-bit ELF executable.
    void *Loader32ExeFile;

    //! @brief The size of the 32-bit loader program image in memory.
    uint32_t Loader32ImageSize;
    uint32_t Reserved5;

    //! @brief The address of the start of the 32-bit loader image in memory.
    void *Loader32ProcessImageBase; // +12

    //! @brief The address of the end of the end of the 32-bit loader image.
    void *Loader32ProcessImageEnd; // +16

    //! @brief The entry point function into the 32-bit loader image.
    void *Loader32EntryPoint; // +20

    //! @brief A pointer to the start of the global descriptor table.
    uint32_t *GlobalDescriptorTable; // +24

    //! @brief A pointer to the start of the interrupt descriptor table.
    uint32_t *InterruptDescriptorTable; // +32
};

//! @brief The pointer to the 16-bit loader environment.
extern struct Loader16Environment *Loader16Env;

//! @brief Switches to real-mode to call a software interrupt.
//! @param[in] interruptId The index if the software interrupt.
//! @param[in,out] regs A pointer to a structure holding the registers on entry
//! to the interrupt, updated with the registers when the call completes.
extern void Interop16Int(uint8_t interruptId, struct Interop16Regs *regs);

//! @brief Switches to real-mode to call 16-bit code.
//! @param[in] realModeSegment The segment of the code to call.
//! @param[in] realModeOffset The offset of the code to call within the segment.
//! @param[in,out] regs A pointer to a structure holding the registers on entry
//! to the subroutine, updated with the registers when it returns.
extern void Interop16FarCall(uint16_t realModeSegment,
                             uint16_t realModeOffset,
                             struct Interop16Regs *regs);

//! @brief Loads the 32-bit page directory base register with an address.
//! @param[in] pageDirPhysAddr32 The 32-bit physical address of the page
//! directory to store in control register CR3.
extern void SetPageDirectory(void * pageDirPhysAddr32);

//! @brief Writes a value to an 8-bit I/O port.
//! @param[in] port The index of the port to write to.
//! @param[in] value The value to write.
extern void WriteToPort8(uint16_t port, uint8_t value);

//! @brief Writes a value to an 16-bit I/O port.
//! @param[in] port The index of the port to write to.
//! @param[in] value The value to write.
extern void WriteToPort16(uint16_t port, uint16_t value);

//! @brief Writes a value to an 32-bit I/O port.
//! @param[in] port The index of the port to write to.
//! @param[in] value The value to write.
extern void WriteToPort32(uint16_t port, uint32_t value);

//! @brief Reads from an 8-bit I/O port.
//! @param[in] port The index of the port to read from.
//! @return The value read from the I/O port.
extern uint8_t ReadFromPort8(uint16_t port);

//! @brief Reads from an 16-bit I/O port.
//! @param[in] port The index of the port to read from.
//! @return The value read from the I/O port.
extern uint16_t ReadFromPort16(uint16_t port);

//! @brief Reads from an 32-bit I/O port.
//! @param[in] port The index of the port to read from.
//! @return The value read from the I/O port.
extern uint32_t ReadFromPort32(uint16_t port);

//! @brief Switches to a 32-bit stack and calls the kernel entry point.
//! @param[in] kernelEntryPoint The virtual address of the entry point to
//! the kernel to call after the stack switch.
//! @param[in] kerenlStackPtr The pointer to the top of the 32-bit kernel stack.
//! @param[in] kernelEnv The environment structure to pass to the kernel.
extern void EnterKernel32(void *kernelEntryPoint,
                          void *kernelStackPtr,
                          /* Environment */ void *kernelEnv);

#endif /* ifndef __ASM__ */


#endif /* header guard */