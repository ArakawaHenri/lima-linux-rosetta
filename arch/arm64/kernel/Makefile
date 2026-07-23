# SPDX-License-Identifier: GPL-2.0
#
# Makefile for the linux kernel.
#

CFLAGS_armv8_deprecated.o := -I$(src)

CFLAGS_REMOVE_ftrace.o = $(CC_FLAGS_FTRACE)
CFLAGS_REMOVE_insn.o = $(CC_FLAGS_FTRACE)
CFLAGS_REMOVE_return_address.o = $(CC_FLAGS_FTRACE)

# Remove stack protector to avoid triggering unneeded stack canary
# checks due to randomize_kstack_offset.
CFLAGS_REMOVE_syscall.o	 = -fstack-protector -fstack-protector-strong
CFLAGS_syscall.o	+= -fno-stack-protector

# When KASAN is enabled, a stack trace is recorded for every alloc/free, which
# can significantly impact performance. Avoid instrumenting the stack trace
# collection code to minimize this impact.
KASAN_SANITIZE_stacktrace.o := n

# It's not safe to invoke KCOV when portions of the kernel environment aren't
# available or are out-of-sync with HW state. Since `noinstr` doesn't always
# inhibit KCOV instrumentation, disable it for the entire compilation unit.
KCOV_INSTRUMENT_entry-common.o := n
KCOV_INSTRUMENT_idle.o := n

# Copyright © 2024 Apple Inc. All Rights Reserved.
# Disclaimer: IMPORTANT: This Apple software is supplied to you by Apple Inc.
# ("Apple") in consideration of your agreement to the following terms, and
# your use, installation, modification or redistribution of this Apple
# software constitutes acceptance of these terms. If you do not agree with
# these terms, please do not use, install, modify or redistribute this Apple
# software.
# In consideration of your agreement to abide by the following terms, and
# subject to these terms, Apple grants you a personal, non-exclusive license,
# under Apple's copyrights in this original Apple software (the "Apple
# Software"), to use, reproduce, modify and redistribute the Apple Software,
# with or without modifications, in source and/or binary forms; provided that
# if you redistribute the Apple Software in its entirety and without
# modifications, you must retain this notice and the following text and
# disclaimers in all such redistributions of the Apple Software. Neither the
# name, trademarks, service marks or logos of Apple Inc. may be used to
# endorse or promote products derived from the Apple Software without specific
# prior written permission from Apple. Except as expressly stated in this
# notice, no other rights or licenses, express or implied, are granted by
# Apple herein, including but not limited to any patent rights that may be
# infringed by your derivative works or by other works in which the Apple
# Software may be incorporated.
# The Apple Software is provided by Apple on an "AS IS" basis. APPLE MAKES NO
# WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
# WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
# COMBINATION WITH YOUR PRODUCTS.
# IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION
# AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER
# THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR
# OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# Object file lists.
obj-y			:= debug-monitors.o entry.o irq.o fpsimd.o		\
			   entry-common.o entry-fpsimd.o process.o ptrace.o	\
			   setup.o signal.o sys.o stacktrace.o time.o traps.o	\
			   io.o vdso.o hyp-stub.o psci.o cpu_ops.o		\
			   return_address.o cpuinfo.o cpu_errata.o		\
			   cpufeature.o alternative.o cacheinfo.o		\
			   smp.o smp_spin_table.o topology.o smccc-call.o	\
			   syscall.o proton-pack.o idle.o patching.o pi/	\
			   rsi.o jump_label.o

obj-$(CONFIG_ARM64_TSO)			+= tso.o
obj-$(CONFIG_COMPAT)			+= sys32.o signal32.o			\
					   sys_compat.o
obj-$(CONFIG_COMPAT)			+= sigreturn32.o
obj-$(CONFIG_COMPAT_ALIGNMENT_FIXUPS)	+= compat_alignment.o
obj-$(CONFIG_KUSER_HELPERS)		+= kuser32.o
obj-$(CONFIG_FUNCTION_TRACER)		+= ftrace.o entry-ftrace.o
obj-$(CONFIG_MODULES)			+= module.o module-plts.o
obj-$(CONFIG_PERF_EVENTS)		+= perf_regs.o perf_callchain.o
obj-$(CONFIG_HARDLOCKUP_DETECTOR_PERF)	+= watchdog_hld.o
obj-$(CONFIG_HAVE_HW_BREAKPOINT)	+= hw_breakpoint.o
obj-$(CONFIG_CPU_PM)			+= sleep.o suspend.o
obj-$(CONFIG_KGDB)			+= kgdb.o
obj-$(CONFIG_EFI)			+= efi.o efi-rt-wrapper.o
obj-$(CONFIG_PCI)			+= pci.o
obj-$(CONFIG_ARMV8_DEPRECATED)		+= armv8_deprecated.o
obj-$(CONFIG_ACPI)			+= acpi.o
obj-$(CONFIG_ACPI_NUMA)			+= acpi_numa.o
obj-$(CONFIG_ARM64_ACPI_PARKING_PROTOCOL)	+= acpi_parking_protocol.o
obj-$(CONFIG_PARAVIRT)			+= paravirt.o
obj-$(CONFIG_RANDOMIZE_BASE)		+= kaslr.o
obj-$(CONFIG_HIBERNATION)		+= hibernate.o hibernate-asm.o
obj-$(CONFIG_ELF_CORE)			+= elfcore.o
obj-$(CONFIG_KEXEC_CORE)		+= machine_kexec.o relocate_kernel.o	\
					   cpu-reset.o
obj-$(CONFIG_KEXEC_FILE)		+= machine_kexec_file.o kexec_image.o
obj-$(CONFIG_ARM64_RELOC_TEST)		+= arm64-reloc-test.o
arm64-reloc-test-y := reloc_test_core.o reloc_test_syms.o
obj-$(CONFIG_CRASH_DUMP)		+= crash_dump.o
obj-$(CONFIG_VMCORE_INFO)		+= vmcore_info.o
obj-$(CONFIG_ARM_SDE_INTERFACE)		+= sdei.o
obj-$(CONFIG_ARM64_PTR_AUTH)		+= pointer_auth.o
obj-$(CONFIG_ARM64_MTE)			+= mte.o
obj-y					+= vdso-wrap.o
obj-$(CONFIG_COMPAT_VDSO)		+= vdso32-wrap.o

# Force dependency (vdso*-wrap.S includes vdso.so through incbin)
$(obj)/vdso-wrap.o: $(obj)/vdso/vdso.so
$(obj)/vdso32-wrap.o: $(obj)/vdso32/vdso.so

obj-y					+= probes/
obj-y					+= head.o
always-$(KBUILD_BUILTIN)		+= vmlinux.lds

ifeq ($(CONFIG_DEBUG_EFI),y)
AFLAGS_head.o += -DVMLINUX_PATH="\"$(abspath vmlinux)\""
endif

# for cleaning
subdir- += vdso vdso32
