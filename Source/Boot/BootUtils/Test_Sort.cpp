//! @file BootUtils/Test_Sort.cpp
//! @brief The definition of unit tests for the abstract sorting algorithm.
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

#include "CollectionTools.hpp"
#include "Loader.hpp"

////////////////////////////////////////////////////////////////////////////////
// Macro Definitions
////////////////////////////////////////////////////////////////////////////////

namespace {
////////////////////////////////////////////////////////////////////////////////
// Local Data Types
////////////////////////////////////////////////////////////////////////////////
using ByteItemTraits = Collection::ItemTraits<uint8_t>;
using ByteComparer = Collection::LessThanComparer<uint8_t>;

using MemMapItemTraits = Collection::ItemTraits<MemMapEntry>;

class MemMapItemComparer : public Collection::IComparer
{
public:
    // Public Types
    using ItemPtr = const MemMapEntry *;

    // Construction/Destruction
    MemMapItemComparer() = default;
    virtual ~MemMapItemComparer() = default;

    // Overrides
    virtual int compare(const void *lhs, const void *rhs) const override
    {
        int diff = 0;

        const auto lhsEntry = static_cast<ItemPtr>(lhs);
        const auto rhsEntry = static_cast<ItemPtr>(rhs);

        if (lhsEntry->BaseAddress == rhsEntry->BaseAddress)
        {
            if (lhsEntry->Size != rhsEntry->Size)
            {
                diff = (lhsEntry->Size < rhsEntry->Size) ? -1 : 1;
            }
        }
        else
        {
            diff = (lhsEntry->BaseAddress < rhsEntry->BaseAddress) ? -1 : 1;
        }

        return diff;
    }
};

////////////////////////////////////////////////////////////////////////////////
// Local Data
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////
GTEST_TEST(Sort, SortSmall)
{
    ByteItemTraits traits;
    ByteComparer comp;

    uint8_t sample[] = { 0xA5, 0x42 };

    // Try sorting no items.
    Collection::sort(&traits, &comp, sample, 0);

    EXPECT_EQ(sample[0], 0xA5);
    EXPECT_EQ(sample[1], 0x42);

    // Try sorting one item.
    Collection::sort(&traits, &comp, sample, 1);

    EXPECT_EQ(sample[0], 0xA5);
    EXPECT_EQ(sample[1], 0x42);

        // Try sorting tw0 item.
    Collection::sort(&traits, &comp, sample, 2);

    EXPECT_EQ(sample[0], 0x42);
    EXPECT_EQ(sample[1], 0xA5);
}

GTEST_TEST(Sort, SortOddNumber)
{
    ByteItemTraits traits;
    ByteComparer comp;

    uint8_t sample[] = { 10, 20, 30, 40, 15, 25, 35 };

    // Try sorting the items.
    Collection::sort(&traits, &comp, sample, std::size(sample));

    static_assert(std::size(sample) == 7, "Array results out of sync.");

    EXPECT_EQ(sample[0], 10);
    EXPECT_EQ(sample[1], 15);
    EXPECT_EQ(sample[2], 20);
    EXPECT_EQ(sample[3], 25);
    EXPECT_EQ(sample[4], 30);
    EXPECT_EQ(sample[5], 35);
    EXPECT_EQ(sample[6], 40);
}

GTEST_TEST(Sort, SortReversedNumber)
{
    ByteItemTraits traits;
    ByteComparer comp;

    uint8_t sample[] = { 45, 40, 35, 30, 25, 20, 15, 10 };

    // Try sorting the items.
    Collection::sort(&traits, &comp, sample, std::size(sample));

    static_assert(std::size(sample) == 8, "Array results out of sync.");

    EXPECT_EQ(sample[0], 10);
    EXPECT_EQ(sample[1], 15);
    EXPECT_EQ(sample[2], 20);
    EXPECT_EQ(sample[3], 25);
    EXPECT_EQ(sample[4], 30);
    EXPECT_EQ(sample[5], 35);
    EXPECT_EQ(sample[6], 40);
    EXPECT_EQ(sample[7], 45);
}

GTEST_TEST(Sort, MemoryRegions)
{
    MemMapEntry entries[] = {
        // Entries added by Loader16.sys
        { 0, 0x10000, MemType::UsableAfterBoot, 0 }, // IVT + IO Transfer Buffer
        { 0x99000, 0x6C00, MemType::UsableAfterBoot, 0 }, // Loader16 Code + Stack + Data

        // Values read when booting a 64 MB Bochs instance.
        { 0x0, 0x9F000, MemType::UsableRAM, 0 }, // Conventional memory up to EBDA [ACPI]
        { 0x9F000, 0x1000, MemType::Reserved, 0 }, // EBDA [ACPI]
        { 0xE8000, 0x18000, MemType::Reserved, 0 }, // High ROM [ACPI]
        { 0x100000, 0x3EF000, MemType::UsableRAM, 0 }, // Extended memory [ACPI]
        { 0x3FF0000, 0x10000, MemType::AcpiReclaimable, 0 }, // ACPI tables? [ACPI]
        { 0xFFFC0000, 0x40000, MemType::Reserved, 0 }, // APIC MMIO? [ACPI]

        // Added by Loader16.sys after memory probing.
        { 0x100000, 0x3000, MemType::UsableAfterBoot, 0 }, // Loader32 Code + Data
    };

    MemMapItemTraits traits;
    MemMapItemComparer comp;

    Collection::sort(&traits, &comp, entries, std::size(entries));

    static_assert(std::size(entries) == 9, "MemMapEntry array out of sync!");
    size_t i = 0;

    EXPECT_EQ(entries[i].BaseAddress, 0);
    EXPECT_EQ(entries[i].Size, 0x10000);
    EXPECT_EQ(entries[i].Type, MemType::UsableAfterBoot);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0);
    EXPECT_EQ(entries[i].Size, 0x9F000);
    EXPECT_EQ(entries[i].Type, MemType::UsableRAM);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0x99000);
    EXPECT_EQ(entries[i].Size, 0x6C00);
    EXPECT_EQ(entries[i].Type, MemType::UsableAfterBoot);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0x9F000);
    EXPECT_EQ(entries[i].Size, 0x1000);
    EXPECT_EQ(entries[i].Type, MemType::Reserved);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0xE8000);
    EXPECT_EQ(entries[i].Size, 0x18000);
    EXPECT_EQ(entries[i].Type, MemType::Reserved);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0x100000);
    EXPECT_EQ(entries[i].Size, 0x3000);
    EXPECT_EQ(entries[i].Type, MemType::UsableAfterBoot);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0x100000);
    EXPECT_EQ(entries[i].Size, 0x3EF000);
    EXPECT_EQ(entries[i].Type, MemType::UsableRAM);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0x3FF0000);
    EXPECT_EQ(entries[i].Size, 0x10000);
    EXPECT_EQ(entries[i].Type, MemType::AcpiReclaimable);
    ++i;

    EXPECT_EQ(entries[i].BaseAddress, 0xFFFC0000);
    EXPECT_EQ(entries[i].Size, 0x40000);
    EXPECT_EQ(entries[i].Type, MemType::Reserved);
    ++i;

    EXPECT_EQ(i, std::size(entries));
}

} // Anonymous namespace

////////////////////////////////////////////////////////////////////////////////

