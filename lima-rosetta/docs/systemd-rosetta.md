# systemd and Rosetta

A modern Fedora x86_64 userspace can start under Rosetta while journald,
D-Bus, or logind die with `SIGTRAP`. Two deterministic interactions are
handled by policy; a third, intermittent failure is a Rosetta bug and must
not be confused with them.

## 1. MemoryDenyWriteExecute

Rosetta is a JIT: a translated process needs writable→executable transitions.
A service that inherits `MemoryDenyWriteExecute=yes` cannot create them after
`execve()`, so the compatibility policy disables MDWE for inner services.

## 2. Seccomp rejection errno

systemd's syscall allowlists reject denied calls with `EPERM` by default. On
the observed Rosetta path that produced repeated traps instead of a usable
fallback. Returning `ENOSYS` lets Rosetta or libc take the normal
"syscall unavailable" path. The allowlists stay in force — only the errno
changes.

The combined policy is installed as a top-level drop-in, so it covers
upgraded and newly installed units without editing RPM-owned files:

```ini
# /etc/systemd/system/service.d/99-rosetta-compat.conf
# /etc/systemd/user/service.d/99-rosetta-compat.conf
[Service]
MemoryDenyWriteExecute=no
SystemCallErrorNumber=ENOSYS
```

## binfmt ownership

Inner and outer systems share one kernel `binfmt_misc` registry. If the inner
`systemd-binfmt.service` reset it, it could delete Lima's Rosetta handler and
break every subsequent x86_64 `execve()`. The inner unit is masked:

```text
/etc/systemd/system/systemd-binfmt.service -> /dev/null
```

The outer Lima-managed system is the sole owner.

## Why systemd-run is used for login sessions

`systemd-run --machine=fedora-x86` places login commands, sudo/PAM sessions,
and their scopes in the machine's cgroup hierarchy with a clean lifetime
boundary. Interactive and noninteractive paths must stay distinct:

```text
SSH with a terminal  -> systemd-run --pty
script or pipeline   -> systemd-run --pipe
```

A nonempty `SSH_ORIGINAL_COMMAND` is not proof of a noninteractive session:
`limactl shell` sends a command that changes directory and execs the login
shell while also allocating a PTY.

## Known issue: Rosetta `/proc/<pid>/exe` assertion

Cold-start testing found a residual, lower-frequency journald failure that is
neither an unsupported instruction nor a TSO context-switch problem. The
ARM64 Rosetta binary executes an intentional `BRK #1`; the core shows:

```text
assertion failed [!readlink_result_self.is_error]:
Could not readlinkat /proc/52/exe
```

journald reads `/proc/<pid>/exe` while collecting metadata about processes
writing to the journal. A short-lived process can exit between enumeration
and lookup, and Rosetta turns that ordinary lookup failure into an internal
assertion instead of returning an error to the translated caller. (The
assertion message does not record the errno, so the race is inferred rather
than proven.)

Experiments that did **not** remove it: clearing the syscall filters and
architecture restriction, disabling journald's sandbox, volatile journal
storage, and pinning journald to one CPU.

The service manager restarts journald and the machine reaches `running`, so
an `active` journald is not proof of a clean boot. No clean, upgrade-proof
systemd-only workaround is currently known; the fix belongs in Rosetta.
Handling:

- provisioning accepts a recovered journald but requires D-Bus and logind to
  have zero restarts;
- `verify-runtime.sh` checks restart counters and the outer coredump
  database, and prints a known-issue warning for the journald assertion;
- `verify-runtime.sh --strict` fails on it — use strict mode when testing a
  new Rosetta or macOS release.

The coredump is stored by the ARM64 outer system because the crashing kernel
task is `/mnt/lima-rosetta/rosetta`, not the inner process. Checking only the
inner `coredumpctl` gives a false green.

## Diagnostics

Inside the x86_64 environment:

```sh
systemctl is-system-running
systemctl --failed
systemctl show systemd-journald \
  -p NRestarts \
  -p MemoryDenyWriteExecute \
  -p SystemCallErrorNumber
busctl --system --no-pager list
coredumpctl --no-pager
```

Expected after a clean boot:

```text
NRestarts=0
MemoryDenyWriteExecute=no
SystemCallErrorNumber=38    # ENOSYS
```

Translated crashes land in the outer system. Inspect it from the ARM64
supervisor (see "Access the ARM64 supervisor" in
[troubleshooting](troubleshooting.md)):

```sh
sudo coredumpctl --no-pager
```
