/*
File:       Loader16.S
Purpose:    Defines the 16-bit entry point for the Helix boot process and
            provides real-mode utilities.
Author:     GiantRobotLemur@na-se.co.uk
Date:       2014-2024
Copyright:  This file is part of the Helix operating system project which is
            released under GPL 3 license. See LICENSE file at the repository
            root or go to https://github.com/GiantRobotLemur/Helix for full
            license details.
*/

#include "Loader_x86.h"

/*
    The boot code is loaded either by BIOS from the CD or from a first stage
    loader from a hard disk partition. It will be loaded to some segment in
    conventional memory, probably 0x07C0:0x0000 but also possibly
    0x0000:0x7C00, certainly on a segment boundary.

    The code is position independent. As long as it is loaded on a 16-byte
    boundary somewhere in conventional memory, running in 16-bit real-mode it can
    calculate its location and update the segment registers so that the code can
    run properly.

    The 16-bit boot loader is relocated to the top of the conventional memory
    i.e. 640Kb - (EBDA 16-bit loader and BSS size). The 16-bit stack is allocated
    below that.

    The 32-bit boot code is flat binary file appended to the end of this
    16-bit loader. It has should be linked with a fixed load address of
    0x100000 (1 MB). The 16-bit code will copy the file contents so that it is
    in the correct position, and it can just be executed from the beginning.

    A 32-bit stack is created below the 16-bit stack. The 16-bit code switches
    to 16-bit protected mode using BIOS and then branches to the 32-bit loader,
    moving to 32-bit protected mode.

    The 16-bit code also contains a real-mode far call/INT emulator which can be
    called from protected mode to use BIOS services. Color

When loaded from CD:

    +---------------------+ 0x7C00 ?
    |  16-bit boot code   |
    +-- 16 byte Boundry --+
    |  32-bit ELF binary  |
    +---------------------+

After relocation:

    +---------------------+ 0x000000
    |  IRQ Vector Table   |
    +---------------------+ 0x000400 - (1 KB)
    |    BIOS Data Area   |
    +---------------------| 0x000600 - (1.5 KB)
    |                     |
    |  Free Conventional  |
    :        Memory       :
    :                     :
    +---------------------+
    |    32-bit Stack     |
    +---------------------+
    |    16-bit Stack     |
    +---------------------+
    |  16-bit Code/Data   |
    +---------------------+
    |     16-bit Bss      |
    +---------------------+ - Value returned by INT 12h
    |   (Optional EBDA)   |
    +---------------------+ 0x0A0000 (640 KB)
    |   Video Memory and  |
    |      BIOS ROMs      |
    +---------------------+ 0x100000 (1 MB)
    |   32-bit Process    |
    |   (Code/Data/Bss)   |
    +---------------------+
    :                     :

    Build with gcc -D__ASM__ --nostdlib -Wl,--oformat=binary,-Ttext=0x0000 \
                    -o Loader16.sys
*/

   .code16
   .text
   .global _start
   .arch i8086
   .org 0

/*****************************************************************************/
/* Entry and position independant initialization                             */
/*****************************************************************************/
_start:

/* The segment address of the 16-bit stack. */
.set Stack16Segment, _start         /* uint16_t */

/* Segment Loader16.sys is moved to in high conventional memory */
.set Code16Segment, _start + 2      /* uint16_t */

/* A 64K-aligned segment used for real-mode I/O operations. */
.set IOSegment, _start + 4          /* uint16_t */

/* The length of the IO segment in 16-byte paragraphs */
.set IOSegmentLength, _start + 6    /* uint16_t */

    /*
    The first two bytes contain a jump instruction but will
    be overwritten with the 16-bit value of the 16-bit stack segment.
    */

    jmp 1f

   .org 8
   /* The following 56 bytes are filled in by genisoimage */
PrimaryVolumeDescSector:
   .int 0
BootFileSector:
   .int 0
BootFileSize:
   .int 0


    .org 64,0
/*
    Define symbols relative to the current address so that we can store
    data fields which overwrite code which is run once at the very start
    of the boot process and never needed again.

    Once processor variant and minimum memory size has been verified,
    the first 512-bytes of the loader are no longer required and can
    be overwritten with runtime data.
*/

/*
    The size of the 16-bit portion of the loader, rounded up to the
    nearest 4 bytes
*/
Loader16Size: /* uint32_t */

/* The offset of the 16-bit entry point in this segment */
.set Interop16Entry, Loader16Size + 4           /* uint16_t */

/* The segment this code was originally loaded to. */
.set OriginalLoadSegment, Loader16Size + 6      /* uint16_t */

/* The INT 0x13 device used for booting */
.set BootDeviceId, Loader16Size + 8             /* uint8_t */

/* @brief The parameters of the boot drive as returned by INT 13h Fn=4Ah */
.set BootDriveParams, Loader16Size + 12         /* uint8_t[32] */

/* The count of entries in MemMapEntries */
.set MemMapEntryCount, BootDriveParams + 32     /* uint32_t */

/* Array of MemMapEntry (20 bytes each) */
.set MemMapEntries, MemMapEntryCount + 4        /* struct MemMapEntry[] */

/*
MemMapEntry structure:
    0x00 : uint64_t BaseAddress
    0x08 : uint64_t Size
    0x10 : uint8_t Type

20 bytes total.
*/


/*
We don't know what offset we are at within the segment, so we
cannot assume that any LEA instructions will get the correct
offset of anything in this segment until we have fixed up
the segment registers to the paragraph starting at _start.

This does rather make the assumption that this code was
loaded on a 16-byte boundary, but if not, we're buggered anyway.
*/
1:
    cli
    movw %cs,%ax    /* Initialise segments and stack */
    subw $16,%ax    /* Set-up a temporary 256 byte stack below this code */
    movw $254,%sp
    movw %ax,%ss

    call LocalOffset    /* Make a short local call to get the segment offset */
LocalOffset:
    popw %bx
    leaw LocalOffset,%cx
    subw %cx,%bx    /* Calculate the offset of _start into the code segment */

    movb $4, %cl
    shrw %cl,%bx    /* Convert the offset to paragraphs */
    movw %cs,%ax
    addw %ax,%bx    /* Calculate the destination segment */
    pushw %bx
    leaw LocalStart,%ax  /* We can't simply push the offset on an i8086 */
    pushw %ax       /* Push the offset and segment for a long return */
    lret
LocalStart:         /* We should now be operating with %cs = (_start >> 4) */
    sti
    movw %bx,%ds    /* Update the segments with the right value */
    movw %bx,%es
    movw %bx,Code16Segment  /* Store the segment address at a known location */
    movw %bx,OriginalLoadSegment  /* Store a copy for after the code is moved */

    /* Store boot parameters */
    movb %dl,BootDeviceId

    /* Set the screen mode to VGA Text 80x25 4 Bpp */
    movw $3,%ax
    int $0x10

/*****************************************************************************/
/* Verify minimum CPU architecture level and features                        */
/*****************************************************************************/
.set FlagsNT, 0x4000
    pushfw
    cli
    pushfw
    popw %ax
    orw $FlagsNT,%ax    /* Set the Nested Task flag */
    pushw %ax
    popfw
    pushfw
    popw %ax
    popfw               /* Restore the flags to their previous state */

    testw $FlagsNT,%ax  /* See if the NT flag was forced to 0 */
    jnz Is32BitCpu
    leaw Error16Bit,%ax
    call Print

Halt8086:
    leaw HaltingMessage,%ax
    call Print
    cli
1:  /* Enter an infinite loop */
    jmp 1b

HaltingMessage:
    .ascii "Halting..."
    .byte 13,10,0

Error16Bit:
    .ascii "16-bit processor detected."
    .byte 13,10,0

CpuIs32Bit:
    .ascii "32-bit or better CPU detected."
    .byte 13,10,0

ErrorXmsNotDetected:
    .ascii "Failed to detect extended memory size."
    .byte 13,10,0

ErrorNotEnoughXms:
    .ascii "Insufficient memory detected."
    .byte 13,10
    .ascii "The system requires at least "
    .ascii MinRamInMbText
    .ascii "Mb to run."
    .byte 13,10,0

ErrorNoCpuId:
    .ascii "CPU Identification not supported."
    .byte 13,10,0

ErrorNonP6Cpu:
    .ascii "A PentiumPro-class CPU or better is required."
    .byte 13,10,0

    .align 4
    .arch i486  /* NOTE: i386 appears to be unrecognised. */

Halt386:
    leaw HaltingMessage,%ax
    call Print
    cli
1:
    hlt
    jmp 1b

Is32BitCpu:
    leaw CpuIs32Bit,%ax
    call Print

   /* Continue probing the CPU capabilities */
.set EFlagsId, 0x200000
    pushfl            /* Store a copy of the flags while probing */
    pushfl
    popl %eax
    movl %eax,%ebx    /* Store a copy of the unmodified flags */
    xorl $EFlagsId,%eax  /* Flip the ID bit */
    pushl %eax        /* Pass the modified value through EFlags */
    popfl
    pushfl
    popl %eax
    popfl             /* Restore the original EFlags */
    andl $EFlagsId,%eax  /* Mask all but the ID bit */
    testl %ebx,%eax   /* See if the bit has changed */
    jz HasCpuID

    leaw ErrorNoCpuId,%ax
    call Print        /* Display an error message and halt. */
    jmp Halt386

    .arch i586        /* We have determined that CPUID is available */
HasCpuID:
    xorl %eax,%eax
    incw %ax
    cpuid

    movb %ah, %bl     /* Get the CPU family */
    andb $0x0F, %bl
    cmpb $6,%bl
    jge 1f
    leaw ErrorNonP6Cpu,%ax
    call Print        /* The CPU is less than a Pentium Pro/K6 */
    jmp Halt386

/*****************************************************************************/
/* Verify minimum amount of system memory to boot                            */
/*****************************************************************************/

1:
    /* All code from here can use 686-specific instructions */
.arch i686

    /* Ensure the system has enough memory to at least boot. */
    movw $0x8800,%ax     /* Select function 0x88 */
    int $0x15            /* Get the size of the extended memory (up to 64MB)*/
    jc FailedToDetectXms /* Carry flag set on error */
    cmpb $0x80,%ah       /* Check for an error code */
    je FailedToDetectXms
    cmpb $0x86,%ah       /* Check for an alternate error code */
    je FailedToDetectXms

    cmp $MinXmsInKb,%ax  /* Check there is enough extended memory */
    jb NotEnoughXms
    jmp RelocateLoader

FailedToDetectXms:
    leaw ErrorXmsNotDetected,%ax
    call Print
    jmp Halt386

NotEnoughXms:
    leaw ErrorNotEnoughXms,%ax
    call Print
    jmp Halt386

/*****************************************************************************/
/* Relocate 16-bit loader to high conventional memory                        */
/*****************************************************************************/
/*
    uint32_t GetConventionalMemTop()

    Gets the address of the top of the conventional memory, rounding down to
    the nearest 4KB boundary as INT 12h and ACPI INT 15h E820h don't
    necessarily agree.
*/
GetConventionalMemTop:
    xorl %eax,%eax
    int $0x12               /* Get the size of the conventional memory in KB */
    cmpw $640,%ax
    jae 1f
    andl $0xFFFFFFFC,%eax   /* Round down to the nearest 4 KB */
1:
    shll $10,%eax
    ret                     /* Return the value in EAX */

RelocateLoader:
    /* Move the 16-bit loader to the top of the conventional memory */
    call GetConventionalMemTop  /* Get the size of the conventional memory */

    xorl %ecx,%ecx
    leaw EndOfLoader16,%cx  /* Get the length of the loader */
    addl $3,%ecx            /* Round up to the nearest 4 bytes */
    andb $0xFC,%cl
    movl %ecx,Loader16Size  /* Store the size of the loader */

    subl %ecx,%eax          /* Calculate the address to move the loader to */
    subl $Loader16BssSize,%eax /* Allocate some extra space for uninitialised data */

    andl $0xFFFFF000,%eax   /* Round down to the nearest 4Kb address */
    shr $4,%eax             /* Calculate the segment */

    movw %ax,%es            /* Setup to move the code */
    xorl %esi,%esi
    xorl %edi,%edi
    shrl $2,%ecx
    rep movsl               /* Move this code */

    pushw %es
    pushw $RelocatedLoader16Entry
    lret                    /* Jump to the copy of this code in its new location */

ErrorEBiosNotSupported:
    .ascii "EBIOS disk functions not supported."
    .byte 13,10,0

ErrorCannotReadBootDrive:
    .ascii "Failed to read boot drive parameters."
    .byte 13,10,0

    .align 4

RelocatedLoader16Entry:
    movw %cs,%ax            /* Set-up the local data segment */
    movw %ds,%bx            /* Store the old 16-bit base segment for later */
    movw %ax,%ds
    movw %ax,Code16Segment  /* Store the new base segment too */
    subw $Stack16Size >> 2,%ax  /* Calculate the new stack location */
    cli                     /* Disable interrupts while switching stacks */
    movw %ax,%ss
    movw $Stack16Size - 4,%sp
    sti                     /* Re-enable interrupts */

    movw %ax,Stack16Segment /* Store a copy of the segment address */


/*****************************************************************************/
/* Probe boot drive parameters                                               */
/*****************************************************************************/

    movb BootDeviceId,%dl       /* Get the boot drive ID */
    movw $0x55AA,%bx            /* Set signature */
    xorl %eax,%eax
    movb $0x41,%ah
    int $0x13                   /* Check EBIOS functions available */
    jc EBiosNotSupported
    cmpw $0xAA55,%bx
    jne EBiosNotSupported
    jmp QueryDriveParams

EBiosNotSupported:
    leaw ErrorEBiosNotSupported,%ax
    call Print
    jmp Halt386

QueryDriveParams:
    leaw BootDriveParams,%si    /* Get a pointer to the block to fill in */
    movw $32,(%si)              /* Set the maximum block size */
    movb $0x48,%ah              /* Set the function code */
    int $0x13                   /* Call EBIOS to get the drive specifications */
    jnc ProbeMemMap
    leaw ErrorCannotReadBootDrive,%ax   /* Display an error message */
    call Print
    jmp Halt386

/*****************************************************************************/
/* Probe the memory map using BIOS services                                  */
/*****************************************************************************/
ProbeMemMap:
    leaw EndOfLoader16,%di  /* Use memory at the end of the loader as scratch space */
    leaw MemMapEntries,%si  /* Get the address of the MemMapEntries array */

    /* Add some memory fixed memory map entries first */
    movl $2,MemMapEntryCount    /* Set the count of entries to 2 to begin with */

    /* Add a memory map entry for the IVT and BIOS data areas */
    /* Possibly round up to 64KB to create an area which can be used for I/O */
    movl $0,(%si)               /* Create an entry for IVT and the BIOS data area */
    movl $0,4(%si)

#ifdef NEEDS_IO_SEGMENT
    movl $0x10000,8(%si)        /* Round up to 64KB to create area for I/O */
    movw $0x60,IOSegment        /* Define the start of the I/O segment */
    movw $0x1000 - 0x60,IOSegmentLength   /* Store the length in paragraphs */
#else
    movl $0x1000,8(%si)         /* Round up to a page boundary */
    movw $0,IOSegment           /* Ensure the I/O segment is marked as unset */
    movw $0,IOSegmentLength
#endif
    movl $0,12(%si)
    movl $MemType_UsableAfterBoot,16(%si)
    addw $MemMapEntry_Size,%si
    incl MemMapEntryCount

    /* Add a memory map entry for the 16-bit loader, data, stacks, etc */
    xorl %edx,%edx
    movw Stack16Segment,%dx /* Calculate the bottom of the 16-bit stack */
    shll $4,%edx
    subl $Stack32Size,%edx  /* Calculate the bottom of the 32-bit stack */
    movl %edx,(%si)         /* Store as the start of the loader region */

    call GetConventionalMemTop  /* Get the top of the conventonal memory in KB */
    subl %edx,%eax          /* Calculate the size of the 16-bit loader image */
    movl %eax,8(%si)
    movl $MemType_UsableAfterBoot,16(%si)
    addw $MemMapEntry_Size,%si
    incl MemMapEntryCount

    /* Add an entry for the flat 32-bit binary at 1 MB */
    movl $0x100000,(%si)
    movl $0,4(%si)
    xorl %edx,%edx              /* Calculate the size of Loader32.sys */
    movl BootFileSize,%eax      /* Get the size of Boot.sys */
    lea EndOfLoader16,%dx
    subl %edx,%eax
    addl $Loader32BssSize,%eax  /* Add BSS space for Loader32.sys */
    addl $0xFFF,%eax            /* Round up to the nearest 4 KB */
    andl $0xFFFFF000,%eax
    movl %eax,8(%si)            /* Store the region size */
    movl $0,12(%si)
    movl $MemType_UsableAfterBoot,16(%si)   /* Set the region type */
    addw $MemMapEntry_Size,%si  /* Increment the entry count */
    incl MemMapEntryCount

    /* Now try getting runtime memory information */

    /* First try ACPI INT 0x15, function 0xE820 */
    xorl %eax,%eax
    xorl %ecx,%ecx
    movw %ds,%ax
    movb $24,%cl            /* Set the size of data allowed */
    movw %ax,%es
    xorl %ebx,%ebx
    movl $0x534D4150,%edx   /* Set the magic number */
    movw $0xE820,%ax        /* Set the function code */
    int $0x15               /* Make the first call */
    jc ACPIMemMapNotSupported
    cmp %eax,%edx           /* See if the magic number was returned in EAX */
    jne ACPIMemMapNotSupported

ProcessAcpiMemMapEntry:
    /* Process memory map entries. */
    movl (%di),%eax         /* Copy the 64-bit base addr and sizes */
    movl 4(%di),%edx
    movl %eax,(%si)
    movl %edx,4(%si)

    movl 8(%di),%eax
    movl 12(%di),%edx
    movl %eax,8(%si)
    movl %edx,12(%si)

    xorl %eax,%eax
    movb 16(%di),%al
    movl %eax,16(%si)       /* Copy the ACPI-compatible type */

    addw $MemMapEntry_Size,%si
    incl MemMapEntryCount

    testl %ebx,%ebx         /* Have we finished the list? */
    jz FinishedMemMap

    /* Reset for the next call */
    movl $24,%ecx
    movl $0x534D4150,%edx   /* Set the magic number */
    movl $0xE820,%eax       /* Set the function code */
    clc                     /* Ensure the carry flag is cleared */
    int $0x15               /* Make the first call */
    jc FinishedMemMap
    jmp ProcessAcpiMemMapEntry

ACPIMemMapNotSupported:
    movl $0x600,%edx        /* Base address, after IVT and BIOS data area */
    movl %edx,(%si)         /* Store the base address */
    movl $0,4(%si)          /* Store the base address (high) */
    call GetConventionalMemTop  /* Get the top of the conventonal memory in KB */
    movl %eax,%ebx          /* Store a copy */
    subl %edx,%eax          /* Calculate the conventional memory size */
    movl %eax,8(%si)        /* Store the conventional memory size */
    movl $0,12(%si)
    movl $MemType_UsableRAM,16(%si) /* Set the type to normal RAM */

    addw $MemMapEntry_Size,%si  /* Move on to the next entry */
    incl MemMapEntryCount

    movl $640 * 1024,%edx   /* Set the start of the reserved area */
    cmpl %ebx,%edx          /* See if there is any space above */
    jb Int15FunctionE801
    movl %eax,(%si)         /* Mark the EBDA as boot-time only */
    movl $0,4(%si)
    sub %ebx,%edx           /* Calculate the size */
    movl %edx,8(%si)
    movl $0,12(%si)
    movl $MemType_UsableAfterBoot,16(%si)

    addw $MemMapEntry_Size,%si  /* Move on to the next entry */
    incl MemMapEntryCount

Int15FunctionE801:
    /* Mark 640 KB to 1 MB as MemType::Reserved */
    movl $(640 * 1024),(%si)
    movl $0,4(%si)
    movl $(480 * 1024),8(%si)
    movl $0,12(%si)
    movl $MemType_UsableAfterBoot,16(%si)

    addw $MemMapEntry_Size,%si  /* Move on to the next entry */
    incl MemMapEntryCount

    /* Next try INT 0x15, function 0xE801 */
    xorl %eax,%eax
    xorl %edx,%edx
    movl %eax,%ebx
    movl %edx,%ecx
    movw $0xE801,%ax        /* Set the function code */
    clc                     /* Clear the carry flag before calling */
    int $0x15               /* Call the function */
    jc Int15FunctionE801NotSupported
    cmpb $0x86,%ah          /* Check - Error: Function not supported */
    je Int15FunctionE801NotSupported
    cmpb $0x80,%ah          /* Check - Error: Invalid command */
    jcxz UseAxAndBx
    movw %cx,%ax            /* Its an alternate form which reports the */
    movw %dx,%bx            /*    values in CX and DX instead of AX and BX */

UseAxAndBx:
    movl $0x100000,(%si)    /* Set base address to 1 MB */
    movl $0,4(%si)
    shll $10,%eax           /* Calculate bytes from 1MB to 16MB */
    movl %eax,8(%si)
    movl $0,12(%si)
    movl $MemType_UsableRAM,16(%si)

    addw $MemMapEntry_Size,%si  /* Move on to the next entry */
    incl MemMapEntryCount

    movl $0x1000000,(%si)   /* Set base address to 16 MB */
    movl $0,4(%si)
    shll $16,%ebx           /* Calculate bytes above 16MB */
    movl %ebx,8(%si)
    movl $0,12(%si)
    movl $MemType_UsableRAM,16(%si)

    addw $MemMapEntry_Size,%si  /* Move on to the next entry */
    incl MemMapEntryCount
    jmp FinishedMemMap

Int15FunctionE801NotSupported:
    /* Last chance: try INT 0x15, function 0x88 */
    /* We've already called this function, so we know it works */
    movl $0x8800,%eax           /* Select Function 0x88 */
    int $0x15                   /* Get KB above 1 MB in AX */
    movl $0x100000,(%si)        /* Set base address to 1 MB */
    movl $0,4(%si)
    shll $10,%eax               /* Calculate bytes from 1MB to 16MB */
    movl %eax,8(%si)
    movl $0,12(%si)
    movl $MemType_UsableRAM,16(%si)

    incl MemMapEntryCount       /* Increment the count of regions */

FinishedMemMap:

/*****************************************************************************/
/* Switch to protected mode to give access to the 32-bit address space       */
/*****************************************************************************/
    jmp Do32BitSetup

A20FailureMessage:
    .ascii "BIOS failed to enable access to the extended memory."
    .byte 13,10,0

ModeSwitchFailMessage:
    .ascii "BIOS failed to switch to protected mode."
    .byte 13,10,0

InvalidExeMessage:
    .ascii "The 32-bit loader is not a valid 32-bit ELF executable."
    .byte 13,10,0

    .align 16
/*
Note: The descriptors are ordered to be compatible
with BIOS INT 0x15 Function 0x89 (Switch to Protected Mode)
as this handles activating the A20 address line and remapping
hardware interrupts.
*/

GdtStart:
    .int 0, 0      /* A null descriptor */

    /* GDT alias descriptor */
    .word GdtEnd - GdtStart - 1   /* Table limit */
    .word 0x0000      /* Base low 16-bits (set at runtime) */
    .byte 0x00        /* Base mid 8-bits (set at runtime) */
    .byte 0x92        /* Type: Present | Writable | Data */
    .byte 0x00        /* Limit high + type (16-bit | Byte Granularity) */
    .byte 0x00        /* Base high 8-bits */

    /* IDT alias descriptor */
    .word 0x07FF      /* 2Kb limit */
    .word 0x0000      /* Base low 16-bits (set at runtime) */
    .byte 0x00        /* Base mid 8-bits (set at runtime) */
    .byte 0x92        /* Type: Present | Writable | Data */
    .byte 0x00        /* Limit high + type (16-bit | Byte Granularity) */
    .byte 0x00        /* Base high 8-bits */

    /* 16-bit data (DS) */
    .word 0xFFFF      /* 64Kb limit */
    .word 0x0000      /* Base low 16-bits (set at runtime) */
    .byte 0x00        /* Base mid 8-bits (set at runtime) */
    .byte 0x92        /* Type: Present | Writable | Data */
    .byte 0x00        /* Limit high + type (16-bit | Byte Granularity) */
    .byte 0x00        /* Base high 8-bits */

    /* 32-bit data (ES) */
    .word 0xFFFF      /* 4Gb limit */
    .word 0x0000      /* Base low 16-bits */
    .byte 0x00        /* Base mid 8-bits */
    .byte 0x92        /* Type: Present | Writable | Data */
    .byte 0xCF        /* Limit high + type (32-bit | Page Granularity) */
    .byte 0x00        /* Base high 8-bits */

    /* 16-bit stack (SS) */
    .word 0xFFFF      /* 64Kb limit */
    .word 0x0000      /* Base low 16-bits (set at runtime) */
    .byte 0x00        /* Base mid 8-bits (set at runtime) */
    .byte 0x92        /* Type: Present | Writable | Data */
    .byte 0x00        /* Limit high + type (16-bit | Byte Granularity) */
    .byte 0x00        /* Base high 8-bits */

    /* 16-bit code (CS) */
    .word 0xFFFF      /* 64Kb limit */
    .word 0x0000      /* Base low 16-bits (set at runtime) */
    .byte 0x00        /* Base mid 8-bits (set at runtime) */
    .byte 0x9A        /* Type: Present | Readable | Non-conforming | code */
    .byte 0x00        /* Limit high + type (16-bit | Byte Granularity) */
    .byte 0x00        /* Base high 8-bits */

    /* Temporary BIOS code segment descriptor */
    .int 0,0

    /* 32-bit code - (Not used by INT 0x15) */
    .word 0xFFFF      /* 4Gb limit */
    .word 0x0000      /* Base low 16-bits */
    .byte 0x00     /* Base mid 8-bits */
    .byte 0x9A     /* Type: Present | Writable | Non-conforming | Code */
    .byte 0xCF     /* Limit high + type (32-bit | Page Granularity) */
    .byte 0x00     /* Base high 8-bits */
GdtEnd:

/*
Rather than create the entire IDT here, create templates of the three
types of interrupt gate we want and construct the IDT using them.
*/
TemplateSoftwareInterruptGate:
    .word HandleSoftIrq  /* Offset (Bits 0-15) */
    .word GdtCode16      /* Code Selector */
    .word 0x8E00         /* Interrupt Gate + Present + DPL 0 */
    .word 0              /* Offset (Bits 16-31) */

TemplateMasterHardwareInterruptGate:
    .word HandleMasterHardIrq  /* Offset (Bits 0-15) */
    .word GdtCode16     /* Code Selector */
    .word 0x8E00        /* Interrupt Gate + Present + DPL 0 */
    .word 0             /* Offset (Bits 16-31) */

TemplateSlaveHardwareInterruptGate:
    .word HandleSlaveHardIrq  /* Offset (Bits 0-15) */
    .word GdtCode16     /* Code Selector */
    .word 0x8E00        /* Interrupt Gate + Present + DPL 0 */
    .word 0             /* Offset (Bits 16-31) */

SetDescriptorBase:
    /* Sets the base address of a descriptor %ax to the segment in %bx */
    pushw %ax
    pushw %bx
    pushw %si

    andw $0xFFFC,%ax    /* Ensure %ax is the offset of the descriptor */
    leaw GdtStart,%si
    addw %ax,%si    /* Calculate the address of the descriptor */
    movw %bx,%ax    /* Store a copy of the segment */
    shlw $4,%ax     /* Calculate the low 16-bits of the address */
    movw %ax,2(%si)
    shrw $12,%bx    /* Calculate the high 4-bits of the address */
    movb %bl,4(%si)

    popw %si
    popw %bx
    popw %ax
    ret

HandleSoftIrq:
    cli
1:
    hlt
    jmp 1b

HandleMasterHardIrq:
    movb $0x20,%al  /* Set the End of Interrupt (EoI) command */
    outb %al,$0xA0  /* Write to the slave PIC command port */
    outb %al,$0x20  /* Write to the master PIC command port */
    cli
1:
    hlt
    jmp 1b


HandleSlaveHardIrq:
    movb $0x20,%al  /* Set the End of Interrupt (EoI) command */
    outb %al,$0x20  /* Write to the master PIC command port */
    cli
1:
    hlt
    jmp 1b

StoreLinearAddress:
    /* Stores a linear address at %bx calculated from segment %dx, offset %ax */
    pushw %ax
    pushw %bx
    pushw %cx
    pushw %dx

    movw %dx,%cx    /* Keep a copy of the segment */

    shrw $12,%dx    /* Preserve the bits 16-19 */
    shlw $4,%cx     /* Calculate bits 0-15 of the linear address */
    addw %cx,%ax
    adcw $0,%dx     /* Add any carry over to bits 16-19 */
    movw %ax,(%bx)
    movw %dx,2(%bx)

    popw %dx
    popw %cx
    popw %bx
    popw %ax
    ret

Do32BitSetup:
    /* Fix up the linear address of the 16-bit code segment in the GDT */
    movw %ds,%bx
    movw $GdtCode16,%ax
    call SetDescriptorBase

    /* Fix up the linear address of the 16-bit data segment in the GDT */
    movw $GdtData16,%ax
    call SetDescriptorBase

    /* Fix up the linear address of the GDT alias descriptor */
    movw %ds,%dx        /* Get the current data segment */
    leaw GdtStart,%bx   /* Get the offset of the GDT in this segment */
    shrw $4,%bx         /* Convert the offset to paragraphs */
    addw %dx,%bx        /* Get the segment of the GDT */
    movw $GdtGdtAlias,%ax
    call SetDescriptorBase

    /* Fix up the linear address of the IDT alias descriptor */
    leaw IdtStart,%bx   /* Get the offset of the IDT */
    shrw $4,%bx         /* Convert the offset to paragraphs */
    addw %dx,%bx        /* Get the segment of the IDT */
    movw $GdtIdtAlias,%ax
    call SetDescriptorBase

    /* Calculate and set the address of the 16-bit stack */
    movw %ss,%bx        /* Get the current stack segment */
    movw $GdtStack16,%ax /* Get the descriptor to fix up */
    call SetDescriptorBase

    /* Fix up the linear address of the 16-bit entry point function */
    leaw Interop16,%ax
    movw %ax,Interop16Entry /* Store the offset of the interop entry point */

    /* Dynamically construct the IDT */
    leaw IdtStart,%ax   /* Calculate the segment of the IDT */
    movw %ds,%dx
    shrw $4,%ax
    addw %dx,%ax
    movw %ax,%es
    xorw %di,%di
    movw $256,%cx

    /* Load the low and high 32-bit words of the template descriptor */
    movl TemplateSoftwareInterruptGate,%eax
    movl TemplateSoftwareInterruptGate + 4,%edx

    /* Fill the IDT with descritprors for software interrupts */
1:
    movl %eax,%es:(%di)
    movl %edx,%es:4(%di)
    add $8,%di
    loop 1b

    /* Fill 8 descriptors with gates to master PIC Hardware IRQ handling code */
    movw $HardwareIrqBase * 8,%di
    movw $8,%cx

    /* Load the low and high 32-bit words of the template descriptor */
    movl TemplateMasterHardwareInterruptGate,%eax
    movl TemplateMasterHardwareInterruptGate + 4,%edx

    /* Fill 8 descriptors with modified interrupt gates */
1:
    movl %eax,%es:(%di)
    movl %edx,%es:4(%di)
    add $8,%di
    loop 1b

    /* Fill another 8 descriptors with entry points which will reset both */
    /* PICs when a hardware IRQ occurs. */
    movw $8,%cx

    /* Load the low and high 32-bit words of the template descriptor */
    movl TemplateSlaveHardwareInterruptGate,%eax
    movl TemplateSlaveHardwareInterruptGate + 4,%edx

    /* Fill 8 descriptors with modified interrupt gates */
1:
    movl %eax,%es:(%di)
    movl %edx,%es:4(%di)
    add $8,%di
    loop 1b

/*
Call BIOS to deal with enabling the A20 address line,
remapping and disabling hardware interrupts and
switching to protected mode.
*/
    movw $0x8900,%ax
    movb $HardwareIrqBase,%bh
    movb $HardwareIrqBase + 8,%bl
    movw %ds,%dx
    movw %dx,%es
    leaw GdtStart,%si
    int $0x15               /* Switch to Protected Mode */

    jnc InitProtectedMode   /* Check the results of the function */
    cmpb $0xFF,%ah          /* Test for A20 failure */
    je A20Fail

    leaw ModeSwitchFailMessage,%ax   /* Test for switch failure */
    call Print
    jmp Halt386

A20Fail:
    leaw A20FailureMessage,%ax
    call Print
    jmp Halt386

/* Print(near char *str[%ax]) - Must be 8086 compatible code. */
    .arch i8086
Print:
    pushw %es
    pushw %bp
    pushw %bx
    pushw %cx
    pushw %dx

    movw %ax,%bp
    movw %ax,%bx
1:
    /* Calculate the string length */
    movb %ds:(%bx),%al   /* Load a character from the string. */
    cmpb $0,%al     /* Is it the null character? */
    je 2f

    out %al,$0xE9   /* Output to the Bochs debug port */

    incw %bx
    jmp 1b

2:
    subw %bp,%bx
    pushw %bx       /* Store the string length */
    mov %ds,%bx
    mov %bx,%es
    movw $0x300,%ax /* Selection function 0x300 */
    xorw %bx,%bx    /* Select video page 0 */
    int $0x10       /* Read the cursor position */

    popw %cx        /* Get the string length back */
    movw $0x1301,%ax  /* Selection function 0x13, sub function 1 */
    movw $0x07,%bx  /* Write white text on black background */
    int $0x10       /* Write the string using video BIOS */

    popw %dx        /* Restore registers and return */
    popw %cx
    popw %bx
    popw %bp
    popw %es
    ret

.arch i686

/* void ZeroMemory32(EAX=DestVirtAddr, EBX=ByteCount)
   Zeros a specified number of bytes in the 32-bit address space.
   DestVirtAddr must be 32-bit aligned.
   ByteCount doesn't need to be divisible by 4.
*/
ZeroMemory32:
    pushl %eax
    pushl %ebx
    pushl %ecx
    pushl %edi
    pushw %es

    movl %eax,%edi       /* Setup the destination point. */
    movl %ebx,%ecx       /* Setup the counter */
    shrl $2,%ecx         /* Convert the counter into a number of 32-bit words */
    movw $GdtData32,%ax  /* Use the 32-bit data segment */
    movw %ax,%es
    xorl %eax,%eax       /* Set the value to fill with */
    cld

    addr32 rep stosl     /* Repeatedly store zeros until ECX=0 */

    andl $0x3,%ebx       /* See if there were any odd bytes to copy. */
    testb %bl,%bl
    jz 1f                /* There were no odd bytes to copy */

    movl %ebx,%ecx       /* Setup the counter of odd bytes */
    addr32 rep stosb     /* Store some zero bytes */
1:

    popw %es
    popl %edi
    popl %ecx
    popl %ebx
    popl %eax
    ret

/* void CopyMemory32(EAX=DestVirtAddr, EBX=SourceVirtAddr,
                     ECX=ByteCount, EDX=0 - Forward, else Backward)
   Copies a specified number of bytes anywhere in the 32-bit address space.
   DestVirtAddr and SourceVirtAddr should be 32-bit aligned.
   ByteCount does not have to be divisible by 4.
*/
CopyMemory32:
    pushl %eax
    pushl %ebx
    pushl %ecx
    pushl %esi
    pushl %edi
    pushw %ds
    pushw %es

    movl %eax,%edi       /* Setup the destination pointer. */
    movl %ebx,%esi       /* Setup the source pointer. */
    movl %ecx,%ebx       /* Store a copy of the counter */
    movw $GdtData32,%ax  /* Use the 32-bit data segment */
    movw %ax,%ds
    movw %ax,%es
    shrl $2,%ecx         /* Calculate the number of 32-bit words to copy */
    cld

    addr32 rep movsl     /* Repeatedly copy 32-bit words until ECX=0 */

    andl $0x3,%ebx       /* Calculate how many odd bytes to copy */
    testb %bl,%bl
    jz 1f                /* There are no odd bytes to copy */

    movl %ebx,%ecx       /* Setup the counter again */
    addr32 rep movsb     /* Move bytes this time. */
1:
    popw %es
    popw %ds
    popl %edi
    popl %esi
    popl %ecx
    popl %ebx
    popl %eax
    ret

/* void Print32(AX=NearStrPtr) */
Print32:
/*
TODO: Write raw VGA print at cursor routine here,
including functionality to update the cursor position, scroll the
screen and interpret non-visible characters.
*/
    pushl %eax
    pushl %esi

    xorl %esi,%esi    /* Ensure the upper part of the register is zeroed */
    movw %ax,%si      /* Store the string pointer */

1:
    movb (%si),%al       /* Get the next byte to print */
    testb %al,%al        /* see if the byte was the terminator */
    jz 1f

    out %al,$0xE9        /* Output to the Bochs debug port */
    incw %si             /* Increment the string pointer. */
    jmp 1b               /* Move on to the next character. */
1:
    popl %esi
    popl %eax
    ret

InitProtectedMode:
    /* Update the segment registers with selectors to flush their attributes */
    movw $GdtData16,%ax  /* Flush the selectors */
    movw %ax,%ds         /* Set %ds, %fs and %gs as 16-bit data */
    movw %ax,%fs
    movw %ax,%gs
    movw $GdtData32,%ax  /* Setup %es to access the 32-bit address space */
    movw %ax,%es
    movw $GdtStack16,%ax
    movw %ax,%ss

/*****************************************************************************/
/* Copy the 32-bit flat binary to the 1 MB mark                              */
/*****************************************************************************/
    xorl %ebx,%ebx
    xorl %ecx,%ecx
    leaw EndOfLoader16,%cx  /* Calculate the size of this 16-bit loader */
    movw OriginalLoadSegment,%bx /* Get the original load segment */
    shll $4,%ebx            /* Convert the segment to a linear address */

    addl %ecx,%ebx          /* Calculate the position of the start of the
                               32-bit portion of the loader. */
    movl BootFileSize,%eax  /* Get the total size of Boot.sys */
    subl %ecx,%eax          /* Calculate the size of Loader32.sys */
    movl %eax,%ecx
    movl $0x100000,%eax     /* Set the linear address to copy Loader32.sys to */

    call CopyMemory32

/*****************************************************************************/
/* Enter the 32-bit loader                                                   */
/*****************************************************************************/
    /* Switch to the 32-bit data segments and stack */
Enter32BitLoader:
    xorl %eax,%eax
    movw Stack16Segment,%ax /* Calculate the location of the 16-bit stack */
    shll $4,%eax
    subl $4,%eax            /* Find the top of the 32-bit stack just below */

    cli
    movw $GdtData32,%dx
    movw %dx,%ds
    movw %dx,%es
    movw %dx,%ss
    movl %eax,%esp
    sti

    /* Far jump to the 32-bit loader entry point */
    xorl %eax,%eax
    xorl %edx,%edx

    movw %fs:Code16Segment,%ax /* Get the address of the 16-bit environment */
    shll $4,%eax

    pushl $GdtCode32            /* Push the far address of the entry point */
    pushl $0x100000
    data32 lret                 /* Jump the the adress if the entry point */

    .arch i686


/*****************************************************************************/
/* A 16-bit interop function to be called from the 32-bit EXE                */
/*****************************************************************************/
Interop16:
/*
Calls a 16-bit real mode entry point or interrupt from 32-bit protected mode.
Entry:   16-bit protected mode code
      32-bit protected mode data
      32-bit protected mode stack
      eax := segment:offset to call, or 0xFFFF:<INT no> for an interrupt.
      ebx := 32-bit linear address of register data structure
Exit:    All registers preserved, the register data structure is updated.


Method:
   Setup all structures on the 16-bit stack, switch stacks and
   push/pop/retf as required.

16-bit Stack Structure

Stack Top
2:  Reserved
2:  32 bit Stack Selector
4:  32-bit Stack Pointer
4:  32-bit Frame Pointer
4:  CR0 Protection Enable/Paging Mask
2:  Boot loader CS
2:  Boot loader return IP
2:  Boot loader Flags [if IRQ called]
2:  Interop Target CS
2:  Interop Target IP
36:  Interop 32-bit registers x 9
2:  Boot loader real mode CS segment
2:  Boot loader real mode entry IP
Starting Stack Pointer

*/

/*
These macros assume the size of the register data structure is
36 bytes, but C and Gas macros don't seem to mix.
*/

.set Interop16RegsSize, 36
.set Interop16RegsWords, 9
.set Stack32Selector, -4
.set Stack32Ptr, -8
.set Stack32FramePtr, -12
.set PModeReturnCs, -14
.set PModeReturnIp, -16
.set ReturnedRegs, (-20 - Interop16RegsSize)
.set Cr0Mask, -20
.set BootFlags, -22
.set BootReturnCs, -24
.set BootReturnIp, -26
.set InteropCs, -28
.set InteropIp, -30
.set InteropRegs, (-32 - Interop16RegsSize)
.set RealModeCs, (-34 - Interop16RegsSize)
.set RealModeIp, (-36 - Interop16RegsSize)

    pushl %ebp
    movl %esp, %ebp
    subl $12,%esp   /* Setup the 32-bit stack frame */
    pushal          /* Preserve all general purpose registers */
    pushl %gs       /* Preserve segment registers */
    pushl %fs
    pushl %es
    pushl %ds
    movl %eax,-4(%ebp)   /* The interop far call or interrupt */
    movl %ebx,-8(%ebp)   /* Store the register data pointer */
    movl %eax,-12(%ebp)  /* Store the effective entry point address */

    movw $GdtStack16,%dx /* Address the 16-bit data and stack segments */
    movw $GdtData16,%cx
    movl $Stack16Size, %ebx
    movw %dx,%es
    movw %cx,%fs

    movl %ss,%eax
    movl %eax,%es:Stack32Selector(%ebx) /* Store Stack32Selector */
    movl %esp,%es:Stack32Ptr(%ebx)      /* Store Stack32Pointer */
    movl %ebp,%es:Stack32FramePtr(%ebx) /* Store StackFrame32Pointer */
    movw %cs,%ax
    lea ReenterProtectedMode,%dx

    movw %ax,%es:PModeReturnCs(%ebx) /* Store a far pointer to the 16-bit */
    movw %dx,%es:PModeReturnIp(%ebx) /*   protected mode reentry */
    pushf
    popw %ax
    movw %ax,%es:BootFlags(%ebx)

    movw -2(%ebp),%ax /* Get the real mode call segment */
    cmpw $0xFFFF,%ax
    jne SetupFarCall

    xorl %edx,%edx
    movb -4(%ebp),%dl   /* Load the interrupt number */
    movl (,%edx,4),%ecx /* Look up the entry point from the interrupt vector table */
    movl %ecx,-12(%ebp) /* Store the effective entry point address */
    leaw IrqReturn,%ax  /* Get the address used to return from an interrupt */
    jmp 1f              /* Setup the real mode return from the interrupt */
SetupFarCall:
    lea FarCallReturn,%ax   /* Setup the real mode return from the far call */
1:
    movw %ax,%es:BootReturnIp(%ebx)
    movw %fs:Code16Segment,%dx
    movw %dx,%es:BootReturnCs(%ebx)
    movw %dx,%es:RealModeCs(%ebx)
    leaw EnterRealMode,%ax  /* Setup the far call entry to real mode */
    movw %ax,%es:RealModeIp(%ebx)

    movl %ebx,%edi          /* Prepare to transfer the register structure */
    subl $-InteropRegs,%edi
    movl -8(%ebp),%esi      /* Get the source address of the register data */
    movl $Interop16RegsWords,%ecx
    cld

    addr32 rep movsl        /* Copy the register data */

    movl -12(%ebp),%eax     /* Get the real mode far pointer to call */
    movl %eax,%es:InteropIp(%ebx) /* Store on the 16-bit stack */

    /* Store a mask of CR0 so that we optionally enable/disable paging too */
    movl %cr0,%eax
    andl $0x80000001,%eax   /* Mask out all but the Paging and Protection enable bits */
    movl %eax,%es:Cr0Mask(%ebx)  /* Store the mask for later */
    movl %eax,%edx          /* Keep a copy for this switch */

    /* Prepare to switch back to real mode */
    movw $GdtData16,%ax     /* Load selectors for 16-bit segments into registers */
    movw %ax,%ds
    movw %ax,%es
    movw %ax,%fs
    movw %ax,%gs
    movw Stack16Segment,%bx /* Load the segment values for after the switch */
    movw Code16Segment,%cx

    /* Disable protection (and optionally paging) */
    movl %cr0,%eax
    andl $0x7FFFFFFE,%eax   /* Clear the protection and paging bits */
    movl %eax,%cr0          /* Switch to real mode */

    movw %bx,%ss            /* Setup the 16-bit stack */
    movl $Stack16Size + RealModeIp,%esp

    movw %cx,%ds            /* Ensure all segment registers are flushed */
    movw %cx,%es
    movw %cx,%fs
    movw %cx,%gs

    retf                    /* Pop the prepared real mode CS:IP off the stack */
EnterRealMode:
    popl %eax               /* Pop the interop registers from the stack */
    popl %ebx
    popl %ecx
    popl %edx
    popl %esi
    popl %edi
    popl %ebp
    popw %ds                /* Pop some extra registers */
    popw %es
    popfl
    addw $2,%sp     /* Re-align the stack so that later 32-bit */
                    /* stack operations are aligned */
    sti             /* Restore interrupts for the real mode call */
    lret            /* Pop the CS:IP of the real mode function to call */

FarCallReturn:
    addw $2,%sp     /* Emulate popf without corrupting registers */
IrqReturn:
    pushfl          /* Store the register contents for return */
    pushw %es
    pushw %ds
    pushl %ebp
    pushl %edi
    pushl %esi
    pushl %edx
    pushl %ecx
    pushl %ebx
    pushl %eax


    /* Prepare to return to 16-bit protected mode */
    cli             /* Disable interrupts again */
    addw $Interop16RegsSize,%sp   /* Adjust the stack */
    popl %edx       /* Get the saved CR0 mask */

    movl %cr0,%eax
    orl %edx,%eax   /* Enable protected mode and possibly paging */
    movl %eax,%cr0

    lret            /* Far call to this segment in protected mode. */
ReenterProtectedMode:
    popl %ebp
    popl %eax       /* Get the old stack details for switching back */
    popl %ebx
    movw %bx,%ss
    movl %eax,%esp

    /* Copy registers from the 16-bit stack to the register structure */
    popl %es            /* Pop the original data segment into %es */
    movw $GdtStack16,%ax
    movw %ax,%ds
    movl -8(%ebp),%edi  /* Get the linear address of the registers structure */
    movl $Stack16Size + ReturnedRegs,%esi
    movl $Interop16RegsWords, %ecx
    cld
    addr32 rep movsl    /* Copy the updated register values back to the
                           input structure */

    movw %es,%ax        /* Restore the 32-bit data segment */
    movw %ax,%ds

    popl %es        /* Restore preserved registers segment */
    popl %fs
    popl %gs

    popal           /* Restore preserved general registers */
    movl %ebp,%esp  /* Restore the previous stack pointer */
    popl %ebp

    data32 lret     /* Return to the 32-bit code */

.align 16           /* Create the IDT in uninitialised memory here */

IdtStart:
EndOfLoader16:

