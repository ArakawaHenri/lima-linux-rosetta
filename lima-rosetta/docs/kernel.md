# Kernel build and provenance

## Source

- Upstream: Linux stable `v6.18.39`, commit
  `f89c296854b755a66657065c35b05406fc18264d`; release tarball SHA-256
  `a7a7e3d2ae9d95e74197223a8d4eb5f6be7aac21b6e6de27e9685d001c1f8cb0`
- Apple patch: written for Linux 6.10, ported here to 6.18.39
- Config baseline:
  `apple/containerization@4f8dc6b53c8557434aafb2d0f7ef454dc0d026bb`

The port keeps Apple's userspace ABI unchanged: `PR_SET_MEM_MODEL` with
`PR_SET_MEM_MODEL_DEFAULT` and `PR_SET_MEM_MODEL_TSO`; there is no
`PR_GET_MEM_MODEL`. The patch is committed in this tree; the same diff is
kept under `kernel/patches/` for rebasing, and `tests/static-checks.sh`
verifies that it still reverse-applies cleanly against the tree.

The port makes two deliberate changes to Apple's 6.10 patch:

- TSO detection moves from rereading `MIDR_EL1`/`AIDR_EL1` on the
  context-switch path to a one-time `ARM64_HAS_TSO` CPU capability. On
  unsupported systems, alternatives patch out the hot-path test and no
  Apple system registers are read per switch; on supported systems the
  switch path reads `ACTLR_EL1` once and writes it only when the incoming
  task needs a different model. The capability framework also supplies
  the secondary-CPU and CPU-hotplug consistency checks.
- `arch_setup_new_exec()` clears the per-thread shadow flag together
  with the hardware bit. The original cleared only the hardware, so a
  child forked between exec and the next context switch could inherit a
  stale TSO shadow and be scheduled with TSO enabled without opting
  in — a performance leak, not a correctness issue, since TSO is the
  stronger memory model.

## Configuration

`configure-kernel.sh` migrates `apple-containerization-config-arm64` with
`olddefconfig`, applies the effective settings from
`config-policy-6.18.39-rosetta-tso-lto`, resolves dependencies again, and
requires every policy line to survive exactly. The same policy validates the
checked-in resolved configuration. Its SHA-256 is:

```text
1c516e3818906283777aff254c4b3bda3bf006f14f3306fa9e68b3c3fb52f53d
```

Key settings:

```text
CONFIG_ARM64_TSO=y
CONFIG_LTO_CLANG_FULL=y                 # not ThinLTO
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y    # upstream -O2, no global -O3
CONFIG_RTC_DRV_PL031=y
CONFIG_VIRTIO_FS=y
CONFIG_BINFMT_MISC=y
CONFIG_CGROUPS=y
CONFIG_NAMESPACES=y
CONFIG_SECCOMP_FILTER=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_LANDLOCK=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_BPF_UNPRIV_DEFAULT_OFF=y
CONFIG_CPU_IDLE=y                       # selected by ACPI_PROCESSOR
CONFIG_THERMAL=y                        # selected by ACPI_PROCESSOR
# CONFIG_DEBUG_FS is not set
# CONFIG_FTRACE is not set
# CONFIG_INPUT is not set               # headless; tiny ACPI power button
# CONFIG_MODULES is not set
```

The policy retains ACPI processor idle and thermal support, which are coherent
dependencies of the VZ ACPI processor driver. It replaces the unused virtual
terminal and input stack with the ACPI tiny power-button driver, and removes
the debugfs and accidentally enabled debug payloads. CFI and shadow call stack
remain disabled to keep this minimal runtime free of constraints unrelated to
the Rosetta workload. Landlock, lockdown, SELinux, and Yama are compiled and
listed in matching initialization order. Lockdown defaults to no enforcement.
BPF LSM is omitted because this kernel does not carry BTF debug information or
install a BPF security policy; unprivileged BPF remains disabled by default.

## Reproducible build

`build-kernel.sh` pins `ARCH=arm64`, `LLVM=1`, the build user/host strings,
and `SOURCE_DATE_EPOCH`/`KBUILD_BUILD_TIMESTAMP` to the upstream release
commit timestamp. It emits the kernel image, `.config`, `System.map`, and a
SHA-256 list. Binary identity still depends on the toolchain; the validated
build used Fedora 44 ARM64 Clang/LLVM/LLD 22.1.8.

## Building from a case-insensitive Mac

Linux contains file names that differ only by case, so a full checkout is not
clean on default APFS. The repository may therefore use a sparse checkout on
macOS while the commits retain the complete tree. `build-with-lima.sh` runs
`git archive HEAD`, extracts the tree inside a case-sensitive Fedora ARM64
VM, and builds there. On Linux or case-sensitive APFS, clone normally.

## Runtime TSO verification

`verify-runtime.sh` requires both calls to succeed in an ARM64 process:

```c
prctl(PR_SET_MEM_MODEL, PR_SET_MEM_MODEL_TSO, 0, 0, 0);
prctl(PR_SET_MEM_MODEL, PR_SET_MEM_MODEL_DEFAULT, 0, 0, 0);
```

It also checks the Rosetta mount, the binfmt registration, the inner x86_64
view, systemd health, and coredump state.
