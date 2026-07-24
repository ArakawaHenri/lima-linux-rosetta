#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
source_dir="$(cd -- "${script_dir}/../.." && pwd -P)"
readonly source_dir
readonly builder="${LIMA_BUILDER:-lima-rosetta-builder}"
readonly local_artifacts="${script_dir}/artifacts"

command -v limactl >/dev/null || {
  printf 'limactl is required\n' >&2
  exit 1
}

if [[ -n "$(git -C "$source_dir" status --short)" ]]; then
  printf 'warning: the working tree is dirty; this command builds HEAD only\n' >&2
fi

status="$(limactl list "$builder" --format '{{.Status}}' 2>/dev/null || true)"
case "$status" in
  Running)
    ;;
  Stopped)
    limactl start "$builder"
    ;;
  "")
    limactl start --name "$builder" "${script_dir}/builder.yaml"
    ;;
  *)
    printf 'builder %s is in unexpected state: %s\n' "$builder" "$status" >&2
    exit 1
    ;;
esac

remote_root="$(
  limactl shell "$builder" -- \
    mktemp -d /var/tmp/lima-linux-rosetta.XXXXXX |
    tr -d '\r'
)"
case "$remote_root" in
  /var/tmp/lima-linux-rosetta.*)
    ;;
  *)
    printf 'refusing unexpected remote temporary path: %s\n' "$remote_root" >&2
    exit 1
    ;;
esac

cleanup() {
  limactl shell "$builder" -- rm -rf -- "$remote_root" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf 'Transferring the committed source tree to %s:%s\n' "$builder" "$remote_root"
git -C "$source_dir" archive --format=tar HEAD |
  limactl shell "$builder" -- tar -xf - -C "$remote_root"

limactl shell "$builder" -- \
  sudo dnf -y --setopt=install_weak_deps=False install \
    bc \
    bison \
    clang \
    cpio \
    dwarves \
    elfutils-libelf-devel \
    flex \
    lld \
    llvm \
    make \
    openssl-devel \
    patch \
    perl \
    python3 \
    rsync \
    tar \
    xz

limactl shell "$builder" -- \
  "$remote_root/lima-rosetta/kernel/build-kernel.sh" \
  "$remote_root/build"

mkdir -p "$local_artifacts"
limactl shell "$builder" -- \
  tar -C "$remote_root/build/artifacts" -cf - . |
  tar -C "$local_artifacts" -xf -

printf 'Copied artifacts to %s\n' "$local_artifacts"
printf 'The reusable builder instance %s was left running.\n' "$builder"
