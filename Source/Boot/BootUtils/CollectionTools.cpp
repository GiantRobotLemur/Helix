//! @file BootUtils/CollectionTools.cpp
//! @brief The definition of a number of utility functions for operating on
//! simple boot-time collections.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Header File Includes
////////////////////////////////////////////////////////////////////////////////
#include "CollectionTools.hpp"

////////////////////////////////////////////////////////////////////////////////
// Macro Definitions
////////////////////////////////////////////////////////////////////////////////

namespace Collection {

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

} // Anonymous namespace

////////////////////////////////////////////////////////////////////////////////
// Xxx Member Definitions
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Global Function Definitions
////////////////////////////////////////////////////////////////////////////////
void sort(const IItemTraits *itemTraits,
          const IComparer *comp,
          void *items, size_t count)
{
    if (count < 2)
        return;

    auto lhsItems = static_cast<uint8_t *>(items);
    size_t stride = itemTraits->getItemSize();

    // Divide the items roughly into halves.
    size_t lowerCount = count / 2;

    // Recursively sort the two halves.
    sort(itemTraits, comp, items, lowerCount);
    sort(itemTraits, comp,
         lhsItems + (stride * lowerCount),
         count - lowerCount);

    // Merge the sorted items in-place.
    auto rhsItems = lhsItems + (stride * lowerCount);
    auto lastLhs = rhsItems - stride;

    // All the left items should appear before all right right items.
    if (comp->compare(lastLhs, rhsItems) <= 0)
        return;

    auto end = lhsItems + (stride * count);

    while (lhsItems < rhsItems)
    {
        int diff = comp->compare(lhsItems, rhsItems);

        if (diff < 0)
        {
            // The left item is already in the right place.
            lhsItems += stride;
        }
        else if (diff > 0)
        {
            // The item on the right needs to go first.
            itemTraits->swap(lhsItems, rhsItems);
            lhsItems += stride;

            // But the item at the head of the right list
            // might be larger than the one after.
            for (auto rhsNext = rhsItems + stride;
                 rhsNext != end;
                 rhsNext += stride)
            {
                auto rhsPrev = rhsNext - stride;
                int rhsDiff = comp->compare(rhsPrev, rhsNext);

                if (rhsDiff > 0)
                {
                    // The next item is less, shuffle the previous
                    // item down.
                    itemTraits->swap(rhsPrev, rhsNext);
                }
                else
                {
                    // The next item is greater or equal, so stop.
                    break;
                }
            }
        }
    }
}

} // namespace Collection
////////////////////////////////////////////////////////////////////////////////

