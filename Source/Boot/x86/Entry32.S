/*
File:       Entry32.S
Purpose:    Defines the 32-bit header and entry point to the code following
            the 16-bit loader.
Author:     GiantRobotLemur@na-se.co.uk
Date:       2016-2024
Copyright:  This file is part of the Helix operating system project which is
            released under GPL 3 license. See LICENSE file at the repository
            root or go to https://github.com/GiantRobotLemur/Helix for full
            license details.
*/

#include "Loader_x86.h"

    .code32
    .text
    .global _start
    .global main
    .arch i686
    .org 0

_start:
    movl %esp,%ebp
    movl %eax,Loader16Env  /* Store the 16-bit environment in a global */

    /* Zero the initialiased data */
    leal BSS_Start,%eax
    leal BSS_End,%edx
    addl $3,%edx            /* Round the end up to the next 4-byte boundary */
    subl %eax,%edx          /* Calculate the size of BSS */
    shrl $2,%edx            /* Calculate as 32-bit words */
    movl %edx,%ecx
    movl %eax,%edi
    xorl %eax,%eax
    cld
    rep stosl               /* Copy zeros into the BSS */

    call initIso9660BootInfo    /* Initialise boot info for an bootable ISO image */

    leal BootInfo,%eax      /* Get a pointer to the initialised BootInfo structure */
    pushl %eax

    call main

HaltBeforeKernel:
    cli
    hlt
    jmp   HaltBeforeKernel

    .align 4
Loader16Env:
    .int 0

/*
void Interop16Int(uint8_t interruptId, Interop16Regs *regs)
*/
    .global Interop16Int
Interop16Int:
    pushl %ebp
    movl %esp,%ebp

    pushl %eax
    pushl %ebx
    pushl %ecx
    pushl %edx

    xorl %edx,%edx
    decl %edx            /* Set all bits of %edx */
    movw 8(%ebp),%dx     /* Get the real mode interrupt */
    xorb %dh,%dh         /* Clear the upper 8-bits */

    xorl %ebx,%ebx       /* Get the 16-bit entry point */
    movl Loader16Env,%eax  /* Get the real mode environment */
    movw Interop16Entry_Offset(%eax),%bx
    pushl %cs            /* Push the return address */
    pushl $1f
    pushl $GdtCode16     /* Push the far pointer to call */
    pushl %ebx
    movl %edx,%eax	     /* Get the real mode interrupt to call */
    movl 12(%ebp),%ebx   /* Get the structure holding the registers */
    lret
1:
    popl %edx
    popl %ecx
    popl %ebx
    popl %eax

    movl %ebp,%esp       /* Restore the old stack frame */
    popl %ebp
    ret


/*
void Interop16FarCall(uint16_t realModeSegment,
                      uint16_t realModeOffset,
                      Interop16Regs *regs)
*/
    .global Interop16FarCall
Interop16FarCall:
    pushl %ebp
    movl %esp,%ebp

    pushl %eax
    pushl %ebx
    pushl %ecx
    pushl %edx

    xorl %ebx,%ebx
    movw %dx,8(%ebp)    /* Get the real mode segment */
    movw %bx,12(%ebp)   /* Get the real mode offset */
    shll $16,%edx
    orl %ebx,%edx       /* Combine the segment and offset */

    xorl %ebx,%ebx      /* Clear the upper bits of %ebx */
    movl Loader16Env,%eax   /* Get the real mode environment */
    movw Interop16Entry_Offset(%eax),%bx
    pushl %cs           /* Push the far return address */
    pushl $1f
    pushl $GdtCode16    /* Push the far pointer entry point */
    pushl %ebx
    movl %edx,%eax      /* Get the real mode far call segment:offset */
    movl 16(%ebp),%ebx  /* Get the structure holding the registers */
    lret
1:
    popl %edx
    popl %ecx
    popl %ebx
    popl %eax

    movl %ebp,%esp      /* Restore the old stack frame */
    popl %ebp
    ret

/*
uint32_t EbiosReadSectors(void *destination,
                          uint64_t startSector,
                          uint32_t sectorCount);
*/
EbiosReadSectors:
#define destination 8(%ebp)
#define startSectorLow 12(%ebp)
#define startSectorHi 16(%ebp)
#define sectorCount 20(%ebp)
#define registerSet -36(%ebp)
#define maxReadSectors -40(%ebp)
#define sectorsRead -44(%ebp)
#define diskAccessPacket -48(%ebp)
#define bootDeviceId -52(%ebp)
#define sectorSize -56(%ebp)

#define localWorkspace 64

    pushl %ebp
    movl %esp,%ebp
    subl $localWorkspace,%esp
    pushl %ebx
    pushl %ecx
    pushl %edx
    pushl %esi
    pushl %edi

    xorl %eax,%eax          /* Zero the local variables */
    leal -localWorkspace(%ebp),%edi
    movl $localWorkspace >> 2,%ecx
    cld
    rep stosl

    /* Calculate the maximum number of sectors which can be read */
    movl Loader16Env,%esi       /* Get the 16-bit data segment */
    movb BootDeviceId_Offset(%esi),%al /* Get the boot device ID */
    movzx %al,%eax              /* Extend to 32-bits to write extra zeros */
    movl %eax,bootDeviceId      /* Keep a local copy */
    movw DriveSectorSize_Offset(%esi),%bx   /* Get the sector size */
    movzx %bx,%ebx              /* Extend to 32-bit */
    movl %ebx,sectorSize        /* Store a copy for later */
    movw IOLength_Offset(%esi),%ax  /* Get the length of the I/O buffer */
    movzx %ax,%eax
    decl %eax                   /* Take 16 bytes off the final size */
    shll $4,%eax                /* Calculate the length in bytes */
    div %ebx                    /* Calculate the maximum sectors to read */
    movl $127,%edx              /* Limit to 127 sectors */
    cmpl %edx,%eax
    jbe 1f
    movl %edx,%eax
1:  movl %eax,maxReadSectors    /* Store the result */

    /* Create a Disk Address Packet in conventional memory */
    movw IOSegment_Offset(%esi),%ax /* Get the real-mode I/O buffer */
    movzx %ax,%eax
    movw %ax,%bx                /* Keep a copy of the segment address */
    incw %bx                    /* Increment to the read buffer segment */
    shll $4,%eax                /* Calculate the linear address */
    movl %eax,%edi              /* Use it to create a disk access packet */
    movl %eax,diskAccessPacket  /* Take a copy of the disk access packet pointer */
    movw $16,(%edi)             /* Set the packet size */
    shll $16,%ebx               /* Create a segment with an offset of 0 */
    movl %ebx,4(%edi)           /* Store the target segment with an offset of 0 */
    movl startSectorLow,%eax    /* Copy the 64-bit start sector */
    movl startSectorHi,%edx
    movl %eax,8(%edi)
    movl %edx,12(%edi)

    /* Setup real-mode registers to call INT 13h */
1:  movl diskAccessPacket,%edi  /* Address the Disk Access Packet */
    movl sectorCount,%eax       /* Calculate sectors left to read */
    subl sectorsRead,%eax
    jz EbiosReadSectors_Exit    /* If no sectors left, finish */
    movl maxReadSectors,%ebx
    cmpl %ebx,%eax          /* Calculate the next count of sectors to read */
    jbe 2f
    movl %ebx,%eax          /* Read the maximum number of sectors */
2:  movw %ax,2(%edi)        /* Store the count of sectors to read */

    /* Set the real-mode registers before calling INT 13h */
    leal registerSet,%esi
    movl bootDeviceId,%eax  /* Get the boot device ID */
    movl $0x4200,(%esi)     /* Set the EAX value (AH=42h) */
    movl %eax,12(%esi)      /* Set the EDX value */
    movl %edi,%ebx          /* Get a pointer to the disk access packer */
    shrl $4,%ebx            /* Calculate the segment address */
    movw %bx,28(%esi)       /* Set DS to point to the disk access packet */

    pushl %esi
    pushl $0x13
    call Interop16Int       /* Emulate the real-mode INT call */
    add $8,%esp             /* Clean the stack */
    jc EbiosReadSectors_Exit    /* Check for failure */

    mov diskAccessPacket,%ebx  /* Get the Disk Access Packet */
    movb 2(%ebx),%al        /* Get the number of sectors read */
    movzx %al,%eax          /* Extend to 32-bits */
    test %eax,%eax          /* Determine if any sectors were read */
    jz EbiosReadSectors_Exit    /* Give up if none were read */

    xorl %edx,%edx
    addl %eax,8(%ebx)       /* Add to the sector count to the 64-bit */
    adcl %edx,12(%ebx)      /*   start sector value */
    addl %eax,sectorsRead   /* Update the local sectors read value */

    /* Copy the data from the I/O Buffer to the target buffer */
    movl sectorSize,%ecx
    mull %ecx               /* Calculate the bytes to copy */
    movl destination,%edi
    movl diskAccessPacket,%esi  /* Get the address of the I/O buffer */
    addl $16,%esi
    shrl $2,%ecx            /* Calculate the number of words to copy */
    cld

    rep movsl               /* Copy the bytes as a string operation */
    movl %edi,destination   /* Update the target pointer */

    jmp 1b          /* See if more sectors need to be read */

EbiosReadSectors_Exit:
    movl sectorsRead,%eax   /* Get the function return value */

#undef destination
#undef startSectorLow
#undef startSectorHi
#undef sectorCount
#undef registerSet
#undef maxReadSectors
#undef sectorsRead
#undef diskAccessPacket
#undef bootDeviceId
#undef sectorSize

#undef localWorkspace
    popl %edi
    popl %esi
    popl %edx
    popl %ecx
    popl %ebx
    movl %ebp,%esp
    popl %ebp
    ret


initIso9660BootInfo:
    pushl %ebp
    movl %esp,%ebp      /* Create a stack frame */
    subl $16,%esp
    pushl %eax
    pushl %ebx
    pushl %ecx
    pushl %edx
    pushl %esi

    movl Loader16Env,%esi   /* Get the 16-bit environment */

    movl DriveTotalSectors_Offset(%esi),%eax    /* Copy the total sector count */
    movl (DriveTotalSectors_Offset + 4)(%esi),%edx
    movl %eax,BDI_TotalSectorCount
    movl %edx,BDI_TotalSectorCount + 4

    movw DriveSectorSize_Offset(%esi),%cx       /* Gets the sector size in bytes */
    xorl %eax,%eax

1:  /* Scan for the first set bit to calculate a power of 2 */
    jcxz 1f
    incw %ax
    shrw $1,%cx
    jmp 1b

1:
    decb %al                /* Take one off as we were counting shifts to zero */
    movb %al,BDI_SectorSizePow2

    movl 8(%esi),%eax       /* Get the primary volume desc sector */
    movl %eax,BDI_BootSector

    leal EbiosReadSectors,%edx  /* Set the function used to read sectors */
    movl %edx,BDI_ReadBootSectors

    movl $BootDeviceType_Cdrom,BDI_DeviceType   /* Set boot device type */

    lea BootDeviceInfo,%eax /* Link the BootInfo structure to BootDeviceInfo */
    movl %eax,BI_BootDeviceInfoPtr

    movl MemMapEntryCount_Offset,%eax
    leal MemMapEntries_Offset(%esi),%edx
    movw %ax,BI_MemoryMapCount  /* Define the memory map entries array */
    movl %edx,BI_MemoryMapPtr
initIso9660BootInfo_Exit:
    popl %esi
    popl %edx
    popl %ecx
    popl %ebx
    popl %eax
    movl %ebp,%esp      /* Restore the previous stack frame */
    popl %ebp
    ret

    .align 4
    .bss
BSS_Start:

BootDeviceInfo:
BDI_TotalSectorCount:
    .int 0, 0
BDI_BootSector:
    .int 0, 0
BDI_ReadBootSectors:
    .int 0
BDI_DeviceType:
    .byte 0
BDI_SectorSizePow2:
    .byte 0

BootInfo:
BI_BootDeviceInfoPtr:
    .int 0
BI_MemoryMapPtr:
    .int 0
BI_BootCommandPtr:
    .int 0
BI_MemoryMapCount:
    .word 0

    .align 4
BSS_End: