//! @file BootUtils/MemoryMap.cpp
//! @brief The definition of an object which manages the boot-time memory map.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Header File Includes
////////////////////////////////////////////////////////////////////////////////
#ifdef TEST_BUILD
#include <stdexcept>
#endif // ifdef TEST_BUILD

#include "CollectionTools.hpp"
#include "Loader.hpp"
#include "MemoryMap.hpp"

////////////////////////////////////////////////////////////////////////////////
// Macro Definitions
////////////////////////////////////////////////////////////////////////////////

namespace {
////////////////////////////////////////////////////////////////////////////////
// Local Data Types
////////////////////////////////////////////////////////////////////////////////
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
                diff = (lhsEntry->Size > rhsEntry->Size) ? -1 : 1;
            }
        }
        else
        {
            // Order biggest blocks first when two have the same start address.
            diff = (lhsEntry->BaseAddress < rhsEntry->BaseAddress) ? -1 : 1;
        }

        return diff;
    }
};

////////////////////////////////////////////////////////////////////////////////
// Local Data
////////////////////////////////////////////////////////////////////////////////
#ifdef TEST_BUILD
struct SimulatedMemoryMap
{
    uintptr_t BaseAddr;
    uintptr_t Size;
};

thread_local SimulatedMemoryMap SimulatedMemory = { 0, 0 };
#endif

////////////////////////////////////////////////////////////////////////////////
// Local Functions
////////////////////////////////////////////////////////////////////////////////
//! @brief Determines if the memory described in a region can be directly
//! addressed by the processor in its current mode.
//! @param[in] region The memory region to examine.
//! @retval true The memory region can be wholly accessed.
//! @retval false The memory region is either wholly or partially inaccessible.
#ifdef TEST_BUILD
bool isDirectlyAddressable(const MemMapEntry &region)
{
    // The memory is addressable if the region is within the block of memory
    // simulating the target memory map.
    uint64_t end = region.BaseAddress + region.Size;

    return end <= SimulatedMemory.Size;
}

#else
constexpr bool isDirectlyAddressable(const MemMapEntry &region) noexcept
{
    // The memory is accessible if the target architecture supports it
    // i.e. 32-bit accessing addresses below 4 GB.
    constexpr uint64_t MaxAccessableAddr = static_cast<uint64_t>(UINTPTR_MAX);

    return (region.BaseAddress + region.Size) <= MaxAccessableAddr;
}
#endif

//! @brief Combines the type of overlapping memory regions.
//! @param lhs The type of the first region.
//! @param rhs The type of the second region.
//! @return A combined memory type to apply to shared region.
MemType combineMemoryTypes(MemType lhs, MemType rhs)
{
    MemType combinedType = lhs;

    if (lhs != rhs)
    {
        if (lhs == MemType::UsableRAM)
        {
            combinedType = rhs;
        }
        else if (rhs == MemType::UsableRAM)
        {
            combinedType = lhs;
        }
        else
        {
            combinedType = (lhs < rhs) ? lhs : rhs;
        }
    }

    return combinedType;
}

//! @brief Processes a memory map of possibly overlapping regions into
//! a set of unique regions in address order.
//! @param[in,out] entries The array specifying the memory map and to receive
//! the new memory map entries.
//! @param[in] count The count of entries in \p entries.
//! @param[in] tempArray A pointer to an array which can be used as
//! temporary storage during processing, assumed to be large enough.
//! @return The new size of the \p entries array or 0 if there was a problem.
//! @note It is assumed that there is enough space at the end of the \p entries
//! to accommodate any further array elements.
size_t consolidateMemoryMap(MemMapEntry *entries, size_t count,
                            MemMapEntry *tempArray)
{
    size_t consolidatedEntryCount = 0;

    if (count > 0)
    {
        // Copy the first region into the target array before processing
        // the rest.
        consolidatedEntryCount = 1;
        *tempArray = *entries;

        for (size_t i = 1; i < count; ++i)
        {
            MemMapEntry &prev = tempArray[consolidatedEntryCount - 1];
            const MemMapEntry &current = entries[i];

            uint64_t prevEnd = prev.BaseAddress + prev.Size;
            uint64_t currentEnd = current.BaseAddress + current.Size;
            uint64_t delta = current.BaseAddress - prev.BaseAddress;

            if (current.BaseAddress < prevEnd)
            {
                // The entries overlap, split entries accordingly.
                if (delta > 0)
                {
                    // Create a copy of the first block to restrict it's size.
                    MemMapEntry &next = tempArray[consolidatedEntryCount++];
                    next = prev;
                    prev.Size = delta;
                    next.BaseAddress += delta;
                    next.Size -= delta;
                }

                // Now deal with blocks with the same base address.
                if (currentEnd == prevEnd)
                {
                    // The blocks wholly overlap.
                    MemMapEntry &next = tempArray[consolidatedEntryCount - 1];

                    next.Type = combineMemoryTypes(next.Type, current.Type);
                }
                else if (currentEnd < prevEnd)
                {
                    // Create a shared entry followed by the rest of the
                    // previous entry.
                    MemMapEntry &shared = tempArray[consolidatedEntryCount - 1];
                    MemMapEntry &next = tempArray[consolidatedEntryCount++];

                    next = shared;
                    next.BaseAddress = currentEnd;
                    shared.Size = current.Size;
                    next.Size -= current.Size;
                    shared.Type = combineMemoryTypes(shared.Type, current.Type);
                }
                else // if (prevEnd < currentEnd)
                {
                    // Create a shared entry followed by the rest of the
                    // current entry.
                    MemMapEntry &shared = tempArray[consolidatedEntryCount - 1];
                    MemMapEntry &next = tempArray[consolidatedEntryCount++];

                    next = current;
                    next.BaseAddress = prevEnd;
                    next.Size = currentEnd - prevEnd;
                    shared.Type = combineMemoryTypes(shared.Type, current.Type);
                }
            }
            else
            {
                // Copy the current entry to the new array.
                tempArray[consolidatedEntryCount++] = current;
            }
        }

        // Overwrite the original array with the temporary values, merging
        // any consecutive regions of the same type.
        entries[0] = tempArray[0];
        size_t j = 1;

        for (size_t i = 1; i < consolidatedEntryCount; ++i)
        {
            MemMapEntry &prev = entries[j - 1];
            MemMapEntry &next = tempArray[i];
            uint64_t prevEnd = prev.BaseAddress + prev.Size;

            if ((next.BaseAddress == prevEnd) &&
                (prev.Type == next.Type))
            {
                // The regions should be merged.
                prev.Size += next.Size;
            }
            else
            {
                // The regions are distinct.
                entries[j++] = next;
            }
        }

        consolidatedEntryCount = j;
    }

    return consolidatedEntryCount;
}

} // Anonymous namespace

////////////////////////////////////////////////////////////////////////////////
// MemoryMap Member Definitions
////////////////////////////////////////////////////////////////////////////////
//! @brief Constructs an object to manage the system memory map during boot time.
MemoryMap::MemoryMap() :
    _allRegions(nullptr),
    _regionCount(0)
{
}

//! @brief Gets the count of regions in the memory map.
size_t MemoryMap::getRegionCount() const { return _regionCount; }

//! @brief Gets the array of memory regions.
const MemMapEntry *MemoryMap::getRegions() const { return _allRegions; }

//! @brief Determines if a memory region is wholly accessible in the current
//! processor mode.
//! @param[in] index The 0-based index of the region to query.
//! @retval true The memory region can be wholly accessed.
//! @retval false The memory region is either wholly or partially inaccessible.
bool MemoryMap::isRegionAccessable(size_t index) const
{
    return (index < _regionCount) ? isDirectlyAddressable(_allRegions[index]) :
                                    false;
}

//! @brief Initialises the memory map from an unordered and possibly
//! overlapping set of memory regions.
//! @param[in] entries The array of entries stored in static memory with an
//! capacity expected to be able to accommodate any increases in size.
//! @param[in] count The count of elements in \p entries.
//! @return A boolean value indicating whether initialisation was successful.
bool MemoryMap::initialise(MemMapEntry *entries, size_t count)
{
    bool isOK = false;

    _allRegions = entries;

    if (_allRegions == nullptr)
    {
        _regionCount = 0;
    }
    else
    {
        _regionCount = count;

        // Sort the regions into address and then size order.
        MemMapItemTraits regionTraits;
        MemMapItemComparer comparer;

        Collection::sort(&regionTraits, &comparer, entries, count);

        // Calculate the required size of a temporary block of memory in which
        // to process the regions into.
        size_t minSizeRequired = (_regionCount * 2) * sizeof(MemMapEntry);
        uint64_t bestBaseAddr = 0;
        uint64_t bestSize = 0;

        // Find a block of memory to use as temporary storage for the
        // consolidated memory map entries.
        for (size_t i = 0; i < _regionCount; ++i)
        {
            const MemMapEntry &region = _allRegions[i];

            if ((region.Type == MemType::UsableRAM) &&
                isDirectlyAddressable(region) &&
                (region.Size > bestSize))
            {
                // Copy the region and see if it gets reduced by later
                // defined regions.
                uint64_t usableBase = region.BaseAddress;
                uint64_t usableEnd = usableBase + region.Size;

                for (auto j = i + 1; j < _regionCount; ++j)
                {
                    const MemMapEntry &nextRegion = _allRegions[j];

                    if (nextRegion.BaseAddress >= usableEnd)
                        break;

                    if (nextRegion.BaseAddress == usableBase)
                    {
                        usableBase += nextRegion.Size;
                    }
                    else if (nextRegion.BaseAddress < usableEnd)
                    {
                        usableEnd = nextRegion.BaseAddress;
                    }
                }

                if (usableBase < usableEnd)
                {
                    uint64_t usableSize = usableEnd - usableBase;

                    if (usableSize > minSizeRequired)
                    {
                        bestBaseAddr = usableBase;
                        bestSize = usableSize;
                        minSizeRequired = usableSize;
                    }
                }
            }
        }

        if (bestSize > 0)
        {
            // We have found an addressable region of memory we can use
            // for temporary storage.

            // Convert the physical address to a linear address, which will
            // be in a thread-local memory slab if TEST_BUILD defined.
            MemMapEntry *tempArray = getAddress<MemMapEntry>(bestBaseAddr);

            _regionCount = consolidateMemoryMap(_allRegions, _regionCount, tempArray);

            isOK = (_regionCount > 0);
        }
    }

    return isOK;
}

////////////////////////////////////////////////////////////////////////////////
// Global Function Definitions
////////////////////////////////////////////////////////////////////////////////

#ifdef TEST_BUILD
//! @brief Gets the base address which all memory regions are measured
//! relative to.
//! @details
//! When running on target, this function will always return 0. When running
//! inside unit tests, this function will return the base address of the block
//! allocated to emulate the memory map.
void *getSystemBase()
{
    if (SimulatedMemory.BaseAddr == 0)
    {
        throw std::runtime_error("No memory allocated to emulate system memory map!");
    }

    return reinterpret_cast<void *>(SimulatedMemory.BaseAddr);
}

void setSystemBase(void *baseAddr, uintptr_t size)
{
    SimulatedMemory.BaseAddr = reinterpret_cast<uintptr_t>(baseAddr);
    SimulatedMemory.Size = (baseAddr == 0) ? 0 : size;
}
#endif


////////////////////////////////////////////////////////////////////////////////

