# Operations and troubleshooting

## Daily use

```sh
limactl shell fedora-x86
limactl shell fedora-x86 -- uname -m
limactl stop fedora-x86
limactl start fedora-x86
```

Update the x86_64 environment normally:

```sh
sudo dnf upgrade --refresh
systemctl is-system-running --wait
systemctl --failed
```

The inner system has no kernel package, so this never touches the ARM64
kernel. A major Fedora release upgrade is a separate migration: test it
before changing the template's release and rootfs marker.

## Access the ARM64 supervisor

Normal SSH lands in the x86_64 machine. To reach the supervisor, use a fresh
connection — do not reuse Lima's SSH ControlMaster — and the `lima-outer`
prefix:

```sh
ssh \
  -o ControlMaster=no \
  -o ControlPath=none \
  -F ~/.lima/fedora-x86/ssh.config \
  lima-fedora-x86 \
  'lima-outer uname -a'
```

## Bash says "no job control"

```text
bash: cannot set terminal process group (-1): Inappropriate ioctl for device
bash: no job control in this shell
```

The gateway used `systemd-run --pipe` for an interactive shell. Check that
`/usr/local/bin/x86` selects `--pty` when standard input and output are
terminals. Reinstalling the template fixes new instances; an existing
instance has a frozen `lima.yaml` that must carry the corrected gateway
before reboot.

After repair, expect `tty` to print a `/dev/pts/*` device, `set -o | grep
monitor` to be on, and `jobs -l` to list a backgrounded `sleep`.

## systemd services produce SIGTRAP

Check the effective policy:

```sh
systemctl show systemd-journald \
  -p MemoryDenyWriteExecute \
  -p SystemCallErrorNumber
```

Expected: `MemoryDenyWriteExecute=no`, `SystemCallErrorNumber=38` (ENOSYS).

Then inspect inner and outer state:

```sh
systemctl --failed
journalctl -b -u systemd-journald -u dbus-broker -u systemd-logind
coredumpctl --no-pager
```

And in the ARM64 supervisor (see above), where translated crashes land:

```sh
sudo coredumpctl --no-pager
```

Translated crashes appear in the **outer** coredump database, so a recovered
journald can look healthy while an outer `SIGTRAP` core proves otherwise. If
journald recovered and no other translated process crashed, this is the known
Rosetta `/proc/<pid>/exe` assertion — see [systemd and
Rosetta](systemd-rosetta.md). Do not pin an obsolete systemd build; the
policy lives in `/etc`, outside RPM-owned files.

## x86_64 programs stop executing

From the supervisor:

```sh
test -x /mnt/lima-rosetta/rosetta
cat /proc/sys/fs/binfmt_misc/rosetta   # must say "enabled"
systemctl status rosetta-ready.service
```

Also confirm the inner `systemd-binfmt.service` is masked; it must not manage
the shared registry.

## systemd-nspawn is not running

From the supervisor:

```sh
machinectl status fedora-x86
systemctl status systemd-nspawn@fedora-x86.service
journalctl -b -u rosetta-ready.service -u systemd-nspawn@fedora-x86.service
```

Provisioning validates Rosetta before starting the machine and retries the
nspawn unit on transient failure.

## `uname -m` says x86_64, but the kernel is ARM64

Working as intended: `uname` is an x86_64 binary and Rosetta presents the
translated view. Run `uname -m` in the ARM64 supervisor (see above) for the
real architecture.

## Reinstall the template

Installing again is idempotent when the files match:

```sh
./lima-rosetta/lima/install.sh
```

If a different kernel or template is already installed, the installer stops;
review the target and use `--force` only when replacement is intentional.

## Full verification

```sh
./lima-rosetta/lima/verify-runtime.sh fedora-x86
./lima-rosetta/lima/verify-runtime.sh --strict fedora-x86
```

The verifier checks the outer kernel, TSO controls, Rosetta registration,
inner architecture, systemd state, core-service restart counters, D-Bus,
inner and outer coredumps, and the noninteractive and interactive PTY gateway
paths. The first command tolerates only the documented journald assertion;
the second requires a completely clean boot.
