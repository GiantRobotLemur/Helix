//! @file BootUtils/Test_TargetTools.cpp
//! @brief The definition of tools used for unit testing code elements as if
//! they were running on the target platform.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Header File Includes
////////////////////////////////////////////////////////////////////////////////
#include <cstring>

#include <algorithm>
#include <iostream>

#include "Test_TargetTools.hpp"

#include "MemoryMap.hpp"

#ifdef _WIN32
#define NOMINMAX
#include <Windows.h>
#else
#include <sys/mman.h>
#endif

////////////////////////////////////////////////////////////////////////////////
// Macro Definitions
////////////////////////////////////////////////////////////////////////////////

namespace {
////////////////////////////////////////////////////////////////////////////////
// Local Data Types
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Local Data
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Local Functions
////////////////////////////////////////////////////////////////////////////////
void *allocateSlab(size_t sizeInMb)
{
    void *slab = nullptr;

    if (sizeInMb > 0)
    {
#ifdef _WIN32
        slab = ::VirtualAlloc(nullptr, sizeInMb << 20,
                              MEM_COMMIT | MEM_RESERVE,
                              PAGE_READWRITE);


        if (slab == nullptr)
#else
        size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
        size_t pageCount = ((sizeInMb << 20) + pageSize - 1) / pageSize;

        slab = ::mmap(nullptr, pageSize * pageCount,
                      PROT_READ | PROT_WRITE,
                      MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);

        if (slab == MAP_FAILED)
#endif
        {
            printf("Error: Failed to allocate simulated memory map of %u Mb\n",
                   static_cast<uint32_t>(sizeInMb));
        }
    }


    return slab;
}

void freeSlab(void *slab, size_t sizeInMb)
{
    if (slab != nullptr)
    {
#ifdef _WIN32
        UNREFERENCED_PARAMETER(sizeInMb);

        BOOL result = ::VirtualFree(slab, 0, MEM_RELEASE);

        if (result == FALSE)
            puts("Error: VirtualFree() failed!");
#else
        size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
        size_t pageCount = ((sizeInMb << 20) + pageSize - 1) / pageSize;
        int result = ::munmap(slab, pageSize * pageCount);

        if (result != 0)
            puts("Error: munmap() failed!");
#endif

    }
}

} // Anonymous namespace

////////////////////////////////////////////////////////////////////////////////
// TargetMemoryMap Member Definitions
////////////////////////////////////////////////////////////////////////////////
TargetMemoryMap::TargetMemoryMap() :
    _memoryMapSize(0),
    _memoryMap(nullptr)
{
}

TargetMemoryMap::TargetMemoryMap(size_t sizeInMb) :
    _memoryMapSize(0),
    _memoryMap(nullptr)
{
    initialise(sizeInMb);
}

TargetMemoryMap::~TargetMemoryMap()
{
    reset();
}

size_t TargetMemoryMap::getSize() const
{
    return _memoryMapSize;
}

void *TargetMemoryMap::getMemoryMap() const
{
    return _memoryMap;
}

void TargetMemoryMap::initialise(size_t sizeInMb)
{
    const size_t sizeInBytes = sizeInMb << 20;

    if (_memoryMapSize != sizeInBytes)
    {
        reset();
    }

    _memoryMap = allocateSlab(sizeInMb);

    if (_memoryMap != nullptr)
    {
        _memoryMapSize = sizeInBytes;

        // Set the slab to be used to simulate the target memory map on the
        // current thread.
        setSystemBase(_memoryMap, _memoryMapSize);
    }
}

void TargetMemoryMap::reset()
{
    if (_memoryMap)
    {
        setSystemBase(nullptr, 0);
        freeSlab(_memoryMap, _memoryMapSize >> 20);
        _memoryMap = nullptr;
    }

    _memoryMapSize = 0;
}


void TargetMemoryMap::fill(size_t startOffset, size_t byteCount, uint8_t pattern)
{
    if (startOffset < _memoryMapSize)
    {
        size_t safeSize = std::min(_memoryMapSize - startOffset, byteCount);

        std::memset(_memoryMap, pattern, safeSize);
    }
}

::testing::AssertionResult TargetMemoryMap::expectMemoryContents(size_t startOffset,
                                                                 size_t byteCount,
                                                                 uint8_t expectedPattern) const
{
    if (startOffset < _memoryMapSize)
    {
        const size_t safeSize = std::min(_memoryMapSize - startOffset, byteCount);
        auto contents = reinterpret_cast<const uint8_t *>(_memoryMap);

        for (size_t i = 0; i < safeSize; ++i)
        {
            if (contents[startOffset + i] != expectedPattern)
            {
                return ::testing::AssertionFailure() <<
                    std::hex << std::setfill('0') << std::setw(2) <<
                    "Unexpected byte value (0x" << contents[startOffset + i] <<
                    ") at target address 0x" << std::setw(8) << (startOffset + i) << ".";
            }
        }
    }

    return ::testing::AssertionSuccess();
}

::testing::AssertionResult TargetMemoryMap::expectMemoryModified(size_t startOffset,
                                                                 size_t byteCount,
                                                                 uint8_t expectedPattern) const
{
    if (startOffset < _memoryMapSize)
    {
        const size_t safeSize = std::min(_memoryMapSize - startOffset, byteCount);
        const uint8_t *contents = reinterpret_cast<const uint8_t *>(_memoryMap);

        for (size_t i = 0; i < safeSize; ++i)
        {
            if (contents[startOffset + i] != expectedPattern)
            {
                // We found a byte which differed from what was expected.
                return ::testing::AssertionSuccess();
            }

            return ::testing::AssertionFailure() <<
                std::hex << std::setfill('0') << std::setw(8) <<
                "No bytes were modified in the range of target addresses from 0x" <<
                startOffset << " to 0x" << (startOffset + safeSize) << ".";
        }
    }

    return ::testing::AssertionFailure() <<
        std::hex << std::setfill('0') << std::setw(8) <<
        "Target base addresses from 0x" << startOffset <<
        " was outside the simulated memory map.";
}

////////////////////////////////////////////////////////////////////////////////
// Global Function Definitions
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////

