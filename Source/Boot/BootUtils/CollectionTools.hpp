//! @file BootUtils/CollectionTools.hpp
//! @brief The declaration of a number of utility functions for operating on
//! simple boot-time collections.
//! @author GiantRobotLemur@na-se.co.uk
//! @date 2024
//! @copyright This file is part of the Helix operating system project which is
//! released under GPL 3 license. See LICENSE file at the repository root or go
//! to https://github.com/GiantRobotLemur/Helix for full license details.
////////////////////////////////////////////////////////////////////////////////

#ifndef __BOOT_UTILS_COLLECTION_TOOLS_HPP__
#define __BOOT_UTILS_COLLECTION_TOOLS_HPP__

////////////////////////////////////////////////////////////////////////////////
// Dependent Header Files
////////////////////////////////////////////////////////////////////////////////
#include <stddef.h>
#include <stdint.h>

namespace Collection {

////////////////////////////////////////////////////////////////////////////////
// Data Type Declarations
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Class Declarations
////////////////////////////////////////////////////////////////////////////////
//! @brief An interface to an object which can manipulate collection items.
class IItemTraits
{
protected:
    // Construction/Destruction
    IItemTraits() = default;
public:
    virtual ~IItemTraits() = default;

    // Accessors
    virtual size_t getItemSize() const = 0;

    // Operations
    virtual void swap(void *lhs, void *rhs) const = 0;
};

//! @brief An interface to an object which compares items of a specific type.
class IComparer
{
protected:
    // Construction/Destruction
    IComparer() = default;
public:
    virtual ~IComparer() = default;

    // Operations
    virtual int compare(const void *lhs, const void *rhs) const = 0;
};

////////////////////////////////////////////////////////////////////////////////
// Function Declarations
////////////////////////////////////////////////////////////////////////////////
void sort(const IItemTraits *itemTraits,
          const IComparer *comp,
          void *items, size_t count);

////////////////////////////////////////////////////////////////////////////////
// Templates
////////////////////////////////////////////////////////////////////////////////
template <typename TItem>
class LessThanComparer : public IComparer
{
public:
    // Public Types
    using ItemPtr = const TItem *;

    // Construction/Destruction
    LessThanComparer() = default;
    virtual ~LessThanComparer() = default;

    // Overrides
    virtual int compare(const void *lhs, const void *rhs) const override
    {
        auto lhsValue = static_cast<ItemPtr>(lhs);
        auto rhsValue = static_cast<ItemPtr>(rhs);

        int diff = 0;

        if (*lhsValue < *rhsValue)
        {
            diff = -1;
        }
        else if (*rhsValue < *lhsValue)
        {
            diff = 1;
        }

        return diff;
    }
};

template<typename TItem>
class ItemTraits : public IItemTraits
{
public:
    // Public Types
    using ItemPtr = TItem *;

    // Construction/Destruction
    ItemTraits() = default;
    virtual ~ItemTraits() = default;

    // Overrides
    virtual size_t getItemSize() const override { return sizeof(TItem); }
    virtual void swap(void *lhs, void *rhs) const override
    {
        auto lhsItem = static_cast<ItemPtr>(lhs);
        auto rhsItem = static_cast<ItemPtr>(rhs);

        TItem temp(*lhsItem);
        *lhsItem = *rhsItem;
        *rhsItem = temp;
    }
};

} // namespace Collection


#endif // Header guard
////////////////////////////////////////////////////////////////////////////////
