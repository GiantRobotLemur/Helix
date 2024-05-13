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
    decl %edx            /* Set all all bits of %edx */
    movw 8(%ebp),%dx     /* Get the real mode interrupt */
    xorb %dh,%dh         /* Clear the upper 8-bits */

    xorl %ebx,%ebx       /* Get the 16-bit entry point */
    movl Loader16Env,%eax  /* Get the real mode environment */
    movw Interop16EntryOffset(%eax),%bx
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
    movw %dx,8(%ebp)     /* Get the real mode segment */
    movw %bx,12(%ebp)    /* Get the real mode offset */
    shll $16,%edx
    orl %ebx,%edx        /* Combine the segment and offset */

    xorl %ebx,%ebx       /* Clear the upper bits of %ebx */
    movl Loader16Env,%eax  /* Get the real mode environment */
    movw Interop16EntryOffset(%eax),%bx
    pushl %cs            /* Push the far return address */
    pushl $1f
    pushl $GdtCode16     /* Push the far pointer entry point */
    pushl %ebx
    movl %edx,%eax       /* Get the real mode far call segment:offset */
    movl 16(%ebp),%ebx   /* Get the structure holding the registers */
    lret
1:
    popl %edx
    popl %ecx
    popl %ebx
    popl %eax

    movl %ebp,%esp       /* Restore the old stack frame */
    popl %ebp
    ret

