# lima-linux-rosetta

An experimental Linux 6.18.39 fork and Lima template for running a complete
Fedora x86_64 userspace on Apple silicon without emulating an x86 machine.

The VM is ARM64 and runs on Virtualization.framework through Lima's `vz`
driver. Apple Rosetta translates x86_64 ELF programs. A minimal Fedora ARM64
supervisor boots a Fedora x86_64 `systemd-nspawn` machine and routes Lima SSH
sessions into it.

[中文](lima-rosetta/docs/README.zh.md)

## Contents

- Linux `v6.18.39`, based on upstream stable commit
  `f89c296854b755a66657065c35b05406fc18264d`.
- Apple's per-thread TSO support, ported from its Linux 6.10 patch and
  committed in this tree.
- The tested Full-LTO ARM64 kernel configuration.
- A Lima template that builds a Fedora 44 x86_64 userspace from signed Fedora
  repositories.
- An upgrade-resistant `/proc/cpuinfo` hook that keeps ordinary x86_64 CPU
  discovery coherent.
- Build, install, runtime-verification, and troubleshooting tools.

The prebuilt kernel is not committed; build artifacts belong in a release,
not in Git history.

## Architecture

```text
Apple-silicon Mac
└── Lima + Virtualization.framework (vz)
    └── Linux 6.18.39 arm64, Full LTO, Apple TSO patch
        └── minimal Fedora 44 arm64 supervisor
            ├── Lima guest agent, SSH, virtiofs, Rosetta + binfmt_misc
            └── systemd-nspawn: Fedora 44 x86_64
                ├── systemd, journald, D-Bus, logind
                ├── dnf and ordinary Fedora packages
                └── interactive and noninteractive Lima shells
```

This is closer to "GNU/x86 on Linux/ARM64" than to an x86 VM: the kernel,
modules, eBPF, KVM, and architecture-specific ioctls remain ARM64.

> [!WARNING]
> The inner system is a developer convenience, not a security boundary. It
> shares the outer VM's ARM64 kernel and network namespace, uses
> `PrivateUsers=no`, and grants the Lima user passwordless sudo: root inside
> the x86_64 environment is effectively root in the outer Lima VM. The macOS
> host remains separated by the VM boundary, and its home directory is
> mounted read-only by default.

## Requirements

- An Apple-silicon Mac with Rosetta for Linux VMs available.
- Lima 2.1 or newer.
- About 8 GiB of VM memory and 80 GiB of virtual disk.
- Internet access for the first build and first provisioning.

```sh
brew install lima
softwareupdate --install-rosetta --agree-to-license
```

## Cloning on macOS

The Linux tree contains names that differ only by case, so a full checkout is
not clean on case-insensitive APFS. Clone without checkout and use the sparse
view:

```sh
git clone --no-checkout <repository-url> lima-linux-rosetta
cd lima-linux-rosetta
git sparse-checkout init --no-cone
git sparse-checkout set \
  '/arch/arm64/' \
  '/include/uapi/linux/prctl.h' \
  '/kernel/' \
  '/README.md' \
  '/CONTRIBUTING.md' \
  '/lima-rosetta/'
git checkout main
```

The commits still contain the complete Linux tree; `build-with-lima.sh`
exports it into a case-sensitive Linux builder. On Linux or case-sensitive
APFS, clone normally.

## Quick start

### 1. Build the kernel

```sh
./lima-rosetta/kernel/build-with-lima.sh
```

The helper creates a Fedora ARM64 builder VM, transfers the committed tree
into its case-sensitive filesystem, and compiles with Clang, LLD, `-O2`, and
Full LTO:

```text
lima-rosetta/kernel/artifacts/Image-6.18.39-rosetta-tso-lto
```

To build directly on an ARM64 Linux host:

```sh
sudo dnf install \
  bc bison clang cpio dwarves elfutils-libelf-devel flex lld llvm make \
  openssl-devel patch perl python3 rsync tar xz
./lima-rosetta/kernel/build-kernel.sh
```

### 2. Install the kernel and template

```sh
./lima-rosetta/lima/install.sh
```

This installs the reusable configuration:

```text
~/.lima/_kernels/6.18.39-rosetta-tso-lto/Image
~/.lima/_templates/fedora-x86.yaml
```

The installed template carries the kernel's absolute path and SHA-256, so
the runtime does not depend on this checkout.

### 3. Create and test the VM

```sh
limactl start --name fedora-x86 template:fedora-x86
./lima-rosetta/lima/verify-runtime.sh fedora-x86
limactl shell fedora-x86
```

The first start downloads the Fedora ARM64 cloud image and builds the x86_64
userspace; later starts reuse it. Inside:

```sh
uname -m                        # x86_64
systemctl is-system-running     # running
sudo dnf upgrade --refresh
```

## systemd compatibility policy

Modern Fedora systemd hits two deterministic Rosetta incompatibilities,
handled by a top-level drop-in for the inner system and user managers:

```ini
[Service]
MemoryDenyWriteExecute=no
SystemCallErrorNumber=ENOSYS
```

Rosetta is a JIT, so MDWE cannot be inherited across `execve()`. A
denied-call errno of `EPERM` made translated services trap instead of falling
back, so the errno becomes `ENOSYS` while the syscall allowlists stay active.
The inner `systemd-binfmt.service` is masked because both systems share one
kernel `binfmt_misc` registry, owned by the outer supervisor. Full failure
chains: [systemd and Rosetta](lima-rosetta/docs/systemd-rosetta.md).

## Coherent CPU identity

Rosetta synthesizes an x86_64 `/proc/cpuinfo` for an absolute-path read, but
util-linux 2.41.5 `lscpu` opens `/proc` and then reads `cpuinfo` relative to
that directory. That path can bypass Rosetta's synthetic view and mix an
x86_64 architecture with ARM fields and feature flags.

The template does not use `LD_PRELOAD`, replace `lscpu`, or hard-code a CPU
model. Before the inner machine starts, an outer service asks Rosetta itself
for the current x86_64 view, validates it, and publishes it atomically. nspawn
then exposes the file to the inner system, where an early mount unit places it
read-only over `/proc/cpuinfo`. It is regenerated on every outer boot, so CPU
count and future Rosetta changes are picked up while malformed output stops
the machine instead of silently leaking ARM data. Files under `/etc` and
`/var/lib/lima-rosetta` are outside RPM ownership, so inner `dnf` upgrades do
not undo the hook.

This fixes conventional userspace discovery only: low-level sysfs, kernel
interfaces, modules, eBPF, and architecture-specific ioctls still describe
the real ARM64 kernel.

## Known issue: intermittent journald SIGTRAP

The tested Rosetta build can assert when journald's read of
`/proc/<pid>/exe` appears to race with a short-lived process exiting.
systemd restarts journald and the machine still reaches `running`; no clean,
upgrade-proof systemd-only workaround is currently known. The smoke test
reports a recovered assertion as a warning; strict mode fails on it:

```sh
./lima-rosetta/lima/verify-runtime.sh --strict fedora-x86
```

## Kernel TSO support

Apple's patch adds per-thread control of `ACTLR_EL1.TSOEN` and the
`PR_SET_MEM_MODEL` prctl used by userspace translators. This port detects the
feature once through the ARM64 CPU capability framework: unsupported systems
get an alternatives-patched branch and never read Apple system registers on
the context-switch path; supported systems read `ACTLR_EL1` once per switch
and write it only when the incoming task needs a different model. Details and
build provenance: [kernel](lima-rosetta/docs/kernel.md).

The included configuration enables:

```text
CONFIG_ARM64_TSO=y
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
CONFIG_LTO_CLANG_FULL=y
# CONFIG_MODULES is not set
```

## Upgrades

- The inner system has no kernel package and Lima boots the digest-pinned
  external `Image`, so `dnf upgrade` cannot replace the ARM64 kernel.
- Compatibility drop-ins live under `/etc/systemd`; RPM upgrades do not
  replace them.
- A major Fedora release upgrade is a separate migration — test it before
  changing the template's release and rootfs marker.

## Documentation

- [Architecture and trust boundaries](lima-rosetta/docs/architecture.md)
- [Kernel build and provenance](lima-rosetta/docs/kernel.md)
- [systemd/Rosetta failure analysis](lima-rosetta/docs/systemd-rosetta.md)
- [Operations and troubleshooting](lima-rosetta/docs/troubleshooting.md)

Primary references:

- [Apple: Running Intel binaries in Linux VMs](https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms)
- [Apple: Accelerating the performance of Rosetta](https://developer.apple.com/documentation/virtualization/accelerating-the-performance-of-rosetta)
- [Lima: Intel-on-ARM and ARM-on-Intel](https://lima-vm.io/docs/config/multi-arch/)
- [Lima: VZ driver](https://lima-vm.io/docs/config/vmtype/vz/)

## Tested state

Tested on Apple M1 with kernel `6.18.39-rosetta-tso-lto`, a Fedora 44 ARM64
supervisor, and a Fedora 44 x86_64 userspace (systemd 259.7): TSO/default
`PR_SET_MEM_MODEL` transitions, coherent `/proc/cpuinfo` and `lscpu`,
journald/dbus-broker/logind, `dnf upgrade`, cold restarts, interactive job
control, noninteractive Lima commands, and strict detection of the journald
assertion above.

## Licensing

GPL-2.0-only; see [COPYING](COPYING). Apple's contributed TSO code carries
its original notice; the permission text is preserved in
[APPLE-PATCH-LICENSE.txt](lima-rosetta/kernel/APPLE-PATCH-LICENSE.txt).

This project is experimental and is not affiliated with or endorsed by Apple,
the Lima project, Fedora, or the Linux kernel project.
