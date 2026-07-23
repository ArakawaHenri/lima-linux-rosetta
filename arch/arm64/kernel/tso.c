// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright © 2024 Apple Inc. All Rights Reserved.
 * Disclaimer: IMPORTANT: This Apple software is supplied to you by Apple Inc.
 * ("Apple") in consideration of your agreement to the following terms, and
 * your use, installation, modification or redistribution of this Apple
 * software constitutes acceptance of these terms. If you do not agree with
 * these terms, please do not use, install, modify or redistribute this Apple
 * software.
 * In consideration of your agreement to abide by the following terms, and
 * subject to these terms, Apple grants you a personal, non-exclusive license,
 * under Apple's copyrights in this original Apple software (the "Apple
 * Software"), to use, reproduce, modify and redistribute the Apple Software,
 * with or without modifications, in source and/or binary forms; provided that
 * if you redistribute the Apple Software in its entirety and without
 * modifications, you must retain this notice and the following text and
 * disclaimers in all such redistributions of the Apple Software. Neither the
 * name, trademarks, service marks or logos of Apple Inc. may be used to
 * endorse or promote products derived from the Apple Software without specific
 * prior written permission from Apple. Except as expressly stated in this
 * notice, no other rights or licenses, express or implied, are granted by
 * Apple herein, including but not limited to any patent rights that may be
 * infringed by your derivative works or by other works in which the Apple
 * Software may be incorporated.
 * The Apple Software is provided by Apple on an "AS IS" basis. APPLE MAKES NO
 * WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
 * WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
 * COMBINATION WITH YOUR PRODUCTS.
 * IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION
 * AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER
 * THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR
 * OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <linux/sched.h>
#include <linux/types.h>

#include <asm/processor.h>
#include <asm/sysreg.h>
#include <asm/tso.h>

#ifdef CONFIG_ARM64_TSO

static u64 read_tso_register(void)
{
	return read_sysreg(actlr_el1);
}

static bool tso_enabled(u64 actlr_el1)
{
	return !!(actlr_el1 & SYS_ACTLR_EL1_TSOEN_MASK);
}

static void write_tso_enable(u64 actlr_el1, bool tso_enable)
{
	u64 new_actlr_el1 =
		(actlr_el1 & ~SYS_ACTLR_EL1_TSOEN_MASK) |
		(tso_enable << SYS_ACTLR_EL1_TSOEN_SHIFT);

	write_sysreg(new_actlr_el1, actlr_el1);
}

int modify_tso_enable(bool tso_enable)
{
	u64 actlr_el1;

	if (!system_supports_tso())
		return -EOPNOTSUPP;

	actlr_el1 = read_tso_register();
	if (tso_enabled(actlr_el1) == tso_enable)
		return 0;

	write_tso_enable(actlr_el1, tso_enable);

	if (tso_enabled(read_tso_register()) != tso_enable)
		return -EOPNOTSUPP;

	return 0;
}

void tso_thread_switch(struct task_struct *next)
{
	u64 actlr_el1 = read_tso_register();

	current->thread.tso = tso_enabled(actlr_el1);
	if (current->thread.tso != next->thread.tso)
		write_tso_enable(actlr_el1, next->thread.tso);
}

#endif /* CONFIG_ARM64_TSO */
