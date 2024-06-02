//! @file BootUtils/Test_MemoryMap.cpp
//! @brief The definition of unit tests for the MemoryMap class.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Header File Includes
////////////////////////////////////////////////////////////////////////////////
#include <gtest/gtest.h>

#include "Loader.hpp"
#include "MemoryMap.hpp"
#include "Test_TargetTools.hpp"

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
const char *memTypeToString(MemType memType)
{
    switch (memType)
    {
    case MemType::Unknown: return "Unknown";
    case MemType::UsableRAM: return "Usable RAM";
    case MemType::Reserved: return "Reserved";
    case MemType::AcpiReclaimable: return "ACPI Reclaimable";
    case MemType::AcpiNvs: return "ACPI NVS";
    case MemType::BadMemory: return "Bad Memory";

    case MemType::UsableAfterBoot: return "Usable After Boot";
    case MemType::KernelImage: return "Kernel Image";
    case MemType::DriverImage: return "Driver Image";

    default: return "Undefined";
    }
}


////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////
class MemMapTest : public ::testing::Test
{
private:
    static constexpr size_t RamSizeInMb = 16;
    static constexpr uint8_t InitialPattern = 0xDF;
    TargetMemoryMap _targetMemory;

protected:
    TargetMemoryMap &getTargetMemory() { return _targetMemory; }

    ::testing::AssertionResult expectUnmodified(size_t baseAddr, size_t size) const
    {
        return _targetMemory.expectMemoryContents(baseAddr, size, InitialPattern);
    }

    ::testing::AssertionResult expectModified(size_t baseAddr, size_t size) const
    {
        return _targetMemory.expectMemoryModified(baseAddr, size, InitialPattern);
    }

    ::testing::AssertionResult expectMemoryRegion(const MemMapEntry &entry,
                                                  uint64_t baseAddr, uint64_t size,
                                                  MemType regionType) const
    {
        ::testing::Message message;
        bool isOK = true;

        if (entry.BaseAddress != baseAddr)
        {
            message << std::hex << std::setfill('0') << std::setw(16) <<
                "Base address incorrect: 0x" << entry.BaseAddress <<
                ", expected 0x" << baseAddr;
            isOK = false;
        }

        if (entry.Size != size)
        {
            if (isOK)
            {
                isOK = false;
            }
            else
            {
                message << '\n';
            }

            message << std::hex << std::setfill('0') << std::setw(16) <<
                "Memory region size incorrect: 0x" << entry.Size <<
                ", expected 0x" << size;
            isOK = false;
        }

        if (entry.Type != regionType)
        {
            if (isOK)
            {
                isOK = false;
            }
            else
            {
                message << '\n';
            }

            message << std::hex << std::setfill('0') << std::setw(16) <<
                "Memory region size incorrect: '" << memTypeToString(entry.Type) <<
                "', expected '" << memTypeToString(regionType) << '\'';
            isOK = false;
        }

        if (isOK)
        {
            return ::testing::AssertionSuccess();
        }
        else
        {
            return ::testing::AssertionFailure(message);
        }
    }

public:
    MemMapTest() :
        _targetMemory(RamSizeInMb)
    {
    }

    void SetUp()
    {
        _targetMemory.fill(0, _targetMemory.getSize(), InitialPattern);
    }
};

TEST_F(MemMapTest, CreateSimpleMemoryMap)
{
    MemMapEntry entries[] = {
        { 0x00, 0xA0000, MemType::UsableRAM, 0 },
        { 0xA0000, 0x60000, MemType::Reserved, 0 },
        { 0x100000, 0xF00000, MemType::UsableRAM, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
    };

    MemoryMap specimen;

    ASSERT_TRUE(specimen.initialise(entries, 3));
    ASSERT_EQ(specimen.getRegions(), entries);
    ASSERT_EQ(specimen.getRegionCount(), 3u);

    size_t i = 0;
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x0, 0xA0000, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xA0000, 0x60000, MemType::Reserved));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x100000, 0xF00000, MemType::UsableRAM));
    EXPECT_TRUE(expectUnmodified(0x00, 0x100000));
    EXPECT_TRUE(expectModified(0x100000, 0xF00000));
}

TEST_F(MemMapTest, CreateUnorderedMemoryMap)
{
    MemMapEntry entries[] = {
        { 0xFFF000, 0x1000, MemType::Reserved, 0 },
        { 0xA0000, 0x60000, MemType::Reserved, 0 },
        { 0x100000, 0xEFF000, MemType::UsableRAM, 0 },
        { 0x00, 0xA0000, MemType::UsableRAM, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
    };

    MemoryMap specimen;

    ASSERT_TRUE(specimen.initialise(entries, 4));
    ASSERT_EQ(specimen.getRegions(), entries);
    ASSERT_EQ(specimen.getRegionCount(), 4u);

    size_t i = 0;
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x0, 0xA0000, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xA0000, 0x60000, MemType::Reserved));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x100000, 0xEFF000, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xFFF000, 0x1000, MemType::Reserved));
    EXPECT_TRUE(expectUnmodified(0x00, 0x100000));
    EXPECT_TRUE(expectModified(0x100000, 0xEFF000));
    EXPECT_TRUE(expectUnmodified(0xFFF000, 0x1000));
}

TEST_F(MemMapTest, CreateComplexMemoryMap)
{
    MemMapEntry entries[] = {
        // Entries added by Loader16.sys
        { 0, 0x10000, MemType::UsableAfterBoot, 0 }, // IVT + IO Transfer Buffer
        { 0x98400, 0x6C00, MemType::UsableAfterBoot, 0 }, // Loader16 Code + Stack + Data

        // Values read when booting a 64 MB Bochs instance.
        { 0x0, 0x9F000, MemType::UsableRAM, 0 }, // Conventional memory up to EBDA [ACPI]
        { 0x9F000, 0x1000, MemType::Reserved, 0 }, // EBDA [ACPI]
        { 0xE8000, 0x18000, MemType::Reserved, 0 }, // High ROM [ACPI]
        { 0x100000, 0xEF0000, MemType::UsableRAM, 0 }, // Extended memory [ACPI]
        { 0xFF0000, 0x10000, MemType::AcpiReclaimable, 0 }, // ACPI tables? [ACPI]
        { 0xFFFC0000, 0x40000, MemType::Reserved, 0 }, // APIC MMIO? [ACPI]

        // Added by Loader16.sys after memory probing.
        { 0x100000, 0x3000, MemType::UsableAfterBoot, 0 }, // Loader32 Code + Data
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
    };

    MemoryMap specimen;

    ASSERT_TRUE(specimen.initialise(entries, 9));
    ASSERT_EQ(specimen.getRegions(), entries);
    ASSERT_EQ(specimen.getRegionCount(), 9u);

    size_t i = 0;
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x0, 0x10000, MemType::UsableAfterBoot));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x10000, 0x88400, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x98400, 0x6C00, MemType::UsableAfterBoot));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x9F000, 0x1000, MemType::Reserved));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xE8000, 0x18000, MemType::Reserved));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x100000, 0x3000, MemType::UsableAfterBoot));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x103000, 0xEED000, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xFF0000, 0x10000, MemType::AcpiReclaimable));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xFFFC0000, 0x40000, MemType::Reserved));
    EXPECT_TRUE(expectUnmodified(0x00, 0x103000));
    EXPECT_TRUE(expectModified(0x103000, 0xEFD000));
    EXPECT_TRUE(expectUnmodified(0xFF0000, 0x10000));
}



TEST_F(MemMapTest, MergeConsecutiveRegions)
{
    MemMapEntry entries[] = {
        { 0xFFF000, 0x1000, MemType::Reserved, 0 },
        { 0xA0000, 0x20000, MemType::Reserved, 0 },
        { 0x100000, 0xEFF000, MemType::UsableRAM, 0 },
        { 0xC0000, 0x40000, MemType::Reserved, 0 },
        { 0x00, 0xA0000, MemType::UsableRAM, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
        { 0x0, 0x0, MemType::Unknown, 0 },
    };

    MemoryMap specimen;

    ASSERT_TRUE(specimen.initialise(entries, 5));
    ASSERT_EQ(specimen.getRegions(), entries);
    ASSERT_EQ(specimen.getRegionCount(), 4u);

    size_t i = 0;
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x0, 0xA0000, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xA0000, 0x60000, MemType::Reserved));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0x100000, 0xEFF000, MemType::UsableRAM));
    EXPECT_TRUE(expectMemoryRegion(entries[i++], 0xFFF000, 0x1000, MemType::Reserved));
    EXPECT_TRUE(expectUnmodified(0x00, 0x100000));
    EXPECT_TRUE(expectModified(0x100000, 0xEFF000));
    EXPECT_TRUE(expectUnmodified(0xFFF000, 0x1000));
}

} // Anonymous namespace

////////////////////////////////////////////////////////////////////////////////

