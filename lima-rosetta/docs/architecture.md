# Architecture and trust boundaries

## Goal

A normal Fedora x86_64 login environment with native Virtualization.framework
performance and an ARM64 kernel — no QEMU system emulation, and no x86_64
packages mixed into the ARM64 root filesystem.

## Layers

**macOS host.** Lima drives Virtualization.framework through its `vz` driver.
VZ exposes the Rosetta runtime to the guest over a dedicated virtiofs share,
and Lima registers the x86_64 ELF handler through `binfmt_misc`.

**ARM64 supervisor.** The outer Fedora system owns the kernel and boot
process, the Lima guest agent and SSH server, `/mnt/lima-rosetta` and the
binfmt registration, networking, and the nspawn lifecycle. Lima supplies the
custom kernel directly to VZ; it mounts Fedora's Btrfs root without an
initramfs, with everything required built in and loadable modules disabled.

**Fedora x86_64 userspace.** Provisioning builds the inner root from Fedora's
signed repositories:

```sh
dnf --installroot=... --releasever=44 --forcearch=x86_64
```

and boots it with `systemd-nspawn`. The inner PID 1, services, shells, and
dnf are x86_64 ELF programs translated by Rosetta. The machine shares the
outer network namespace and bind-mounts the persistent guest home, the host
home (read-only), Rosetta (read-only), `/usr/lib/modules` (read-only — for
tooling that expects it; x86_64 modules cannot load into an ARM64 kernel),
and the host timezone.

## CPU identity boundary

Rosetta's x86_64 `/proc/cpuinfo` synthesis is path-sensitive in the tested
runtime. A direct absolute-path read receives the translated view, while
util-linux 2.41.5 `lscpu` reaches the file through a directory-relative
`openat()` and can receive the underlying ARM64 procfs data. The result is
internally contradictory: `Architecture: x86_64` alongside ARM CPU fields
and feature flags.

The template makes the conventional userspace view deterministic:

1. `rosetta-cpuinfo.service` runs after Rosetta registration and before the
   main nspawn unit.
2. `/usr/local/libexec/rosetta-cpuinfo` launches a short-lived, non-booted
   nspawn environment and uses the translated `/bin/cat /proc/cpuinfo` to
   obtain Rosetta's own current view.
3. It validates record count, x86 vendor and long-mode fields, rejects ARM
   fields, and atomically publishes
   `/var/lib/lima-rosetta/fedora-x86.cpuinfo`.
4. The nspawn configuration bind-mounts that file at
   `/mnt/lima-cpuinfo`; the inner `proc-cpuinfo.mount` places it read-only
   over `/proc/cpuinfo` before `sysinit.target`.

The generator runs on every outer boot. A changed vCPU count is therefore
reflected automatically, while an incompatible future Rosetta format fails
closed and prevents the inner machine from starting. Neither the generated
file nor the `/etc` mount unit is owned by an inner RPM.

This is an identity compatibility layer, not a second kernel abstraction.
Kernel-facing sysfs entries, modules, eBPF, KVM, and architecture-specific
ioctls continue to expose ARM64 reality.

## SSH gateway

The outer sshd routes sessions through a `ForceCommand` gateway
(`/usr/local/bin/x86`), which dispatches on `SSH_ORIGINAL_COMMAND`. Lima
maintenance traffic (SFTP, SCP, guest agent) and SSH commands beginning with
the `lima-outer ` prefix stay in the ARM64 supervisor; everything else runs
inside the machine via `systemd-run --machine=fedora-x86`.

Using `systemd-run` rather than a raw namespace switch keeps login commands,
sudo/PAM sessions, and their scopes in the machine's cgroup hierarchy, and
gives systemd a clean lifetime boundary for collecting transient units. The
gateway has two paths:

- SSH with a terminal → `systemd-run --pty`
- scripts and pipes → `systemd-run --pipe`

`--pipe` on an interactive shell leaves Bash without a controlling terminal
("no job control"); see [troubleshooting](troubleshooting.md).

## Persistence and upgrades

The inner root filesystem and guest home live on the instance disk. The
installed template and kernel live under `$LIMA_HOME`:

```text
~/.lima/_templates/fedora-x86.yaml
~/.lima/_kernels/6.18.39-rosetta-tso-lto/Image
```

and do not depend on the source checkout. The inner root contains no kernel
package and Lima boots the digest-pinned external image, so `dnf upgrade`
cannot replace the kernel. The CPU-view generator lives in the outer
supervisor, and the inner mount unit lives in `/etc`; ordinary package
upgrades cannot replace either one.

## Security model

> [!WARNING]
> The inner machine is not a security boundary from the outer Lima VM. Do not
> run mutually untrusted or hostile workloads in it.

The design trades isolation for developer convenience:

- passwordless sudo for the Lima user;
- `PrivateUsers=no` — inner root is not remapped;
- shared network namespace (`Private=no`, `VirtualEthernet=no`);
- a necessarily shared ARM64 kernel;
- host home mounted read-only — remove the mount when it is not needed.

Treat root in the x86_64 environment as root-equivalent in the outer Lima VM.
The macOS host remains protected by the Virtualization.framework boundary.
