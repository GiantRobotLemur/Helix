//! @file Loader.hpp
//! @brief The declaration of common structures shared between the
//! boot-method-specific loader stub written in assembly language and the
//! architecture-specific first level boot loader written in C++.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.
////////////////////////////////////////////////////////////////////////////////

#ifndef __HELIX_BOOT_LOADER_HPP__
#define __HELIX_BOOT_LOADER_HPP__

////////////////////////////////////////////////////////////////////////////////
// Dependent Header Files
////////////////////////////////////////////////////////////////////////////////
#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////
// Macro Definitions
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Data Type Declarations
////////////////////////////////////////////////////////////////////////////////
//! @brief Classifies different blocks of memory.
enum class MemType : uint8_t
{
    // Legacy values from PC ACPI BIOS Read Memory Map service (INT 0x15, 0xE820).
    Unknown = 0,
    UsableRAM = 1,
    Reserved = 2,
    AcpiReclaimable = 3,
    AcpiNvs = 4,
    BadMemory = 5,

    // Custom values defined by Helix.
    UsableAfterBoot = 128,
    KernelImage = 129,
    DriverImage = 130,

    Max,
};

//! @brief Specifies the method used to boot the operating system.
enum class BootDeviceType : uint8_t
{
    //! @brief Synonymous with unset or unknown.
    None,

    //! @brief The OS was booted from a floppy disk drive
    FloppyDisk,

    //! @brief The OS was booted from a (partition of?) as hard disk.
    HardDisk,

    //! @brief The OS was booted from an El Torito bootable CD, DVD image,
    //! possibly on a USB stick or memory card.
    CdRom,

    //! @brief The boot loader was read from a local device, but expects the
    //! rest of the operating system to be downloaded via a network interface.
    Network,

    //! @brief The boot loader was read from a local device, but expects the
    //! rest of the operating system to be downloaded via serial port.
    Serial,

    //! @brief A value only used for bounds checking.
    Max,
};

////////////////////////////////////////////////////////////////////////////////
// Class Declarations
////////////////////////////////////////////////////////////////////////////////
//! @brief A structure defining a run of bytes in the memory map.
struct MemMapEntry
{
    //! @brief The physical base address of the region.
    uint64_t BaseAddress;

    //! @brief The count of bytes in the region.
    uint64_t Size;

    //! @brief The classification of the region.
    MemType Type;

    uint8_t Padding[sizeof(uint32_t) - 1];
};

//! @brief A pointer to a function which reads raw blocks from the boot device.
//! @param[in] destination A pointer to the memory to receive the sectors read.
//! @param[in] startSector The (0-based?) index of the first sector to read.
//! @param[in] sectorCount The count of contiguous sectors to read.
//! @return The count of sectors read.
using ReadBootSectorsFn = uint32_t (*)(void *destination, uint64_t startSector,
                                       uint32_t sectorCount);

//! @brief A structure which describes the device used to read further data
//! at boot time: a kernel, drivers, configuration files, etc.
struct BootDeviceInfo
{
    //! @brief The total count of blocks in the storage device.
    uint64_t TotalSectorCount;

    //! @brief The index of the block of the device used to boot the system.
    //! @details
    //! This is boot-device-specific. When booting from a ISO9660 image (CD,
    //! DVD, USB stick, etc.) it represents the block holding the Primary Volume
    //! descriptor.
    uint64_t BootSector;

    //! @brief A pointer to a function which can read further blocks from the
    //! boot device.
    ReadBootSectorsFn ReadBootSectors;

    //! @brief The type of device used for booting.
    BootDeviceType DeviceType;

    //! @brief The size of blocks in the boot device expressed as an even
    //! power of 2.
    uint8_t SectorSizePow2;
};

//! @brief A structure passed to the first level loader in order to prepare
//! and load the operating system.
struct BootInfo
{
    //! @brief A pointer to the object describing the boot device.
    BootDeviceInfo *DeviceInfo;

    //! @brief A pointer to an array of entries defining regions of memory.
    //! @details
    //! The array is not sorted and some entries may overlap, in which case,
    //! entries with more specific semantics take precedence over those which
    //! simply describe normal memory.
    MemMapEntry *MemoryMap;

    //! @brief A pointer to a null-terminated array UTF-8 encoded characters
    //! which encode parameter to the boot process, much like command line options.
    //! @details
    //! The pointer can be nullptr to indicate an empty string. Tokens within the
    //! string can be single or double quoted as necessary. Quotes can be escaped
    //! with a leading slash '\' character within a quoted section.
    char *BootCommand;

    //! @brief Defines the count of entries in the MemoryMap array.
    uint16_t MemoryMapCount;
};

////////////////////////////////////////////////////////////////////////////////
// Function Declarations
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Templates
////////////////////////////////////////////////////////////////////////////////

#endif // Header guard
////////////////////////////////////////////////////////////////////////////////
