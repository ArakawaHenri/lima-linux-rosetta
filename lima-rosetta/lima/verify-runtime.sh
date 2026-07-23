#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

strict=0
if [[ "${1-}" == --strict ]]; then
  strict=1
  shift
fi
if (( $# > 1 )); then
  printf 'usage: %s [--strict] [INSTANCE]\n' "$0" >&2
  exit 2
fi

readonly strict
readonly instance="${1:-fedora-x86}"
readonly lima_home="${LIMA_HOME:-${HOME}/.lima}"
readonly ssh_config="${lima_home}/${instance}/ssh.config"
readonly destination="lima-${instance}"
readonly ssh_args=(
  -o ControlMaster=no
  -o ControlPath=none
  -F "$ssh_config"
)
remote_command='lima-outer sudo bash -s -- 0'
if (( strict != 0 )); then
  remote_command='lima-outer sudo bash -s -- 1'
fi
readonly remote_command

[[ -f "$ssh_config" ]] || {
  printf 'missing Lima SSH config: %s\n' "$ssh_config" >&2
  exit 1
}

# The command is selected from the two constant strings above.
# shellcheck disable=SC2029
ssh "${ssh_args[@]}" "$destination" "$remote_command" <<'OUTER'
set -Eeuo pipefail

readonly strict="${1:?missing strict-mode argument}"
known_issue=0
runtime_failure=0

printf 'outer kernel: '
uname -a
test "$(uname -m)" = aarch64

outer_state=
for _ in $(seq 1 120); do
  outer_state="$(systemctl is-system-running 2>/dev/null || true)"
  [[ "$outer_state" == running ]] && break
  sleep 1
done
printf 'outer state: %s\n' "$outer_state"
test "$outer_state" = running
test -z "$(systemctl --failed --no-legend --plain)"

printf 'Rosetta mount: '
findmnt -n -o FSTYPE,SOURCE /mnt/lima-rosetta
grep -qx enabled /proc/sys/fs/binfmt_misc/rosetta

python3 - <<'PY'
import ctypes

libc = ctypes.CDLL(None, use_errno=True)
pr_set_mem_model = 0x4D4D444C
for value, name in ((1, "TSO"), (0, "default")):
    ctypes.set_errno(0)
    result = libc.prctl(pr_set_mem_model, value, 0, 0, 0)
    error = ctypes.get_errno()
    print(f"memory model {name}: rc={result}, errno={error}")
    if result != 0:
        raise SystemExit(1)
PY

leader="$(machinectl show fedora-x86 -p Leader --value)"
enter=(
  nsenter
  --target "$leader"
  --mount --uts --ipc --net --pid
  --root --wd
)

printf 'inner kernel view: '
"${enter[@]}" /bin/uname -a
test "$("${enter[@]}" /bin/uname -m)" = x86_64
test "$("${enter[@]}" /bin/rpm --eval '%{_arch}')" = x86_64

printf 'inner CPU view:\n'
"${enter[@]}" /usr/local/libexec/rosetta-cpuinfo-check

# The leader's mount table is the machine's mount namespace; reading it
# natively avoids relying on a translated findmnt, which could itself be
# subject to Rosetta's /proc path handling.
awk '$5 == "/proc/cpuinfo" && $6 ~ /(^|,)ro(,|$)/ { ok = 1 } END { exit !ok }' \
  "/proc/$leader/mountinfo"
printf 'cpuinfo bind: read-only /proc/cpuinfo\n'

printf 'inner state: '
"${enter[@]}" /bin/systemctl is-system-running
test -z "$("${enter[@]}" /bin/systemctl --failed --no-legend --plain)"
"${enter[@]}" /bin/systemctl is-active --quiet \
  systemd-journald.service dbus-broker.service systemd-logind.service
for service in \
  systemd-journald.service \
  dbus-broker.service \
  systemd-logind.service; do
  restarts="$("${enter[@]}" /bin/systemctl show \
    --property=NRestarts --value "$service")"
  printf '%s restarts: %s\n' "$service" "$restarts"
  if (( restarts != 0 )); then
    if [[ "$service" == systemd-journald.service ]]; then
      known_issue=1
    else
      runtime_failure=1
    fi
  fi
done
"${enter[@]}" /bin/busctl --system --no-pager list >/dev/null
test "$("${enter[@]}" /bin/coredumpctl --no-pager --no-legend 2>/dev/null | wc -l)" -eq 0

# A translated process is an ARM64 Rosetta process from the shared kernel's
# point of view, so systemd-coredump records its crash in the outer system.
# Looking only at the inner coredump database can therefore produce a false
# green after systemd has automatically restarted a failed service.
boot_id="$(tr -d '-' </proc/sys/kernel/random/boot_id)"
rosetta_cores="$(
  journalctl --no-pager --output=json \
    "_BOOT_ID=$boot_id" \
    COREDUMP_EXE=/mnt/lima-rosetta/rosetta 2>/dev/null |
    awk 'END { print NR + 0 }'
)"
journald_cores="$(
  journalctl --no-pager --output=json \
    "_BOOT_ID=$boot_id" \
    COREDUMP_EXE=/mnt/lima-rosetta/rosetta \
    COREDUMP_COMM=systemd-journal 2>/dev/null |
    awk 'END { print NR + 0 }'
)"
printf 'outer Rosetta coredumps this boot: %s\n' "$rosetta_cores"
if (( rosetta_cores != 0 )); then
  coredumpctl --no-pager --no-legend list "_BOOT_ID=$boot_id" 2>/dev/null |
    awk 'index($0, "/mnt/lima-rosetta/rosetta")'
fi
if (( journald_cores != 0 )); then
  known_issue=1
fi
if (( rosetta_cores != journald_cores )); then
  runtime_failure=1
fi

if (( known_issue != 0 )); then
  printf '%s\n' \
    'warning: known Rosetta /proc/<pid>/exe assertion affected journald' >&2
fi
if (( runtime_failure != 0 || (strict != 0 && known_issue != 0) )); then
  exit 1
fi

if (( known_issue != 0 )); then
  printf 'runtime verification passed with known-issue warning\n'
else
  printf 'runtime verification passed cleanly\n'
fi
OUTER

# Exercise the same gateway used by ordinary `limactl shell` and SSH clients.
# In particular, sudo must remain inside the nspawn cgroup so pam_systemd does
# not leave a failed session scope behind.
ssh "${ssh_args[@]}" "$destination" '
set -Eeuo pipefail
sudo true
test "$(uname -m)" = x86_64
test "$(rpm --eval "%{_arch}")" = x86_64
test "$(systemctl is-system-running)" = running
test -z "$(systemctl --failed --no-legend --plain)"
printf "daily x86 gateway verification passed\n"
'

# Force an SSH PTY and verify that the gateway preserves a controlling
# terminal. This catches the common systemd-run --pipe/job-control regression.
ssh -tt "${ssh_args[@]}" "$destination" '
test -t 0
test -t 1
test "$(tty)" != "not a tty"
printf "interactive PTY gateway verification passed\n"
' </dev/null
