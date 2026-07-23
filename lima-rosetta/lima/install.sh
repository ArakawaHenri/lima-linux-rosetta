#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

readonly release=6.18.39-rosetta-tso-lto
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
project_dir="$(cd -- "${script_dir}/.." && pwd -P)"
readonly project_dir
readonly lima_home="${LIMA_HOME:-${HOME}/.lima}"
readonly kernel_dir="${lima_home}/_kernels/${release}"
readonly template_dir="${lima_home}/_templates"
readonly kernel_target="${kernel_dir}/Image"
readonly template_target="${template_dir}/fedora-x86.yaml"

force=0
if [[ "${1-}" == --force ]]; then
  force=1
  shift
fi

if (( $# > 1 )); then
  printf 'usage: %s [--force] [KERNEL_IMAGE]\n' "$0" >&2
  exit 2
fi

image="${1:-${project_dir}/kernel/artifacts/Image-${release}}"
if [[ ! -f "$image" ]]; then
  fallback="${lima_home}/_kernels/${release}/Image"
  if [[ $# == 0 && -f "$fallback" ]]; then
    image="$fallback"
  else
    printf 'kernel image not found: %s\n' "$image" >&2
    printf 'build it with ../kernel/build-with-lima.sh or pass its path explicitly\n' >&2
    exit 1
  fi
fi
image="$(cd -- "$(dirname -- "$image")" && pwd -P)/$(basename -- "$image")"

sha256_file() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -e "$kernel_target" ]] &&
   ! cmp -s "$image" "$kernel_target" &&
   (( ! force )); then
  printf 'refusing to replace a different kernel: %s\n' "$kernel_target" >&2
  printf 'rerun with --force after reviewing the target\n' >&2
  exit 1
fi

install -d -m 0755 "$kernel_dir" "$template_dir"
if [[ "$image" != "$kernel_target" ]]; then
  install -m 0644 "$image" "${kernel_target}.new"
  mv -f "${kernel_target}.new" "$kernel_target"
fi

kernel_sha256="$(sha256_file "$kernel_target")"
escaped_kernel="$(
  printf '%s' "$kernel_target" |
    sed 's/[\\&|]/\\&/g'
)"

staging="$(mktemp -d "${TMPDIR:-/tmp}/lima-linux-rosetta.XXXXXX")"
cleanup() {
  rm -rf -- "$staging"
}
trap cleanup EXIT

sed \
  -e "s|@@KERNEL_IMAGE@@|${escaped_kernel}|g" \
  -e "s|@@KERNEL_SHA256@@|${kernel_sha256}|g" \
  "${script_dir}/fedora-x86.yaml.in" \
  >"${staging}/fedora-x86.yaml"

if command -v limactl >/dev/null; then
  limactl validate "${staging}/fedora-x86.yaml"
fi

if [[ -e "$template_target" ]] &&
   ! cmp -s "${staging}/fedora-x86.yaml" "$template_target" &&
   (( ! force )); then
  printf 'refusing to replace a different template: %s\n' "$template_target" >&2
  printf 'rerun with --force after reviewing the target\n' >&2
  exit 1
fi

install -m 0644 "${staging}/fedora-x86.yaml" "$template_target"

printf 'Installed kernel:   %s\n' "$kernel_target"
printf 'Kernel SHA-256:     %s\n' "$kernel_sha256"
printf 'Installed template: %s\n' "$template_target"
printf 'Create a VM with:   limactl start --name fedora-x86 template:fedora-x86\n'
