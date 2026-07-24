#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
project_dir="$(cd -- "${script_dir}/.." && pwd -P)"
readonly project_dir
source_dir="$(cd -- "${project_dir}/.." && pwd -P)"
readonly source_dir

bash -n \
  "${project_dir}/kernel/build-kernel.sh" \
  "${project_dir}/kernel/build-with-lima.sh" \
  "${project_dir}/lima/install.sh" \
  "${project_dir}/lima/verify-runtime.sh"
sh -n "${project_dir}/kernel/configure-kernel.sh"

config="${project_dir}/kernel/config-6.18.39-rosetta-tso-lto"
policy="${project_dir}/kernel/config-policy-6.18.39-rosetta-tso-lto"
while IFS= read -r setting || [[ -n "$setting" ]]; do
  case "$setting" in
    ''|'#'|'## '*) continue ;;
    '# CONFIG_'*' is not set'|CONFIG_*=*) ;;
    '# CONFIG_'*)
      printf 'invalid policy setting: %s\n' "$setting" >&2
      exit 1
      ;;
    '# '*) continue ;;
    *)
      printf 'invalid policy setting: %s\n' "$setting" >&2
      exit 1
      ;;
  esac
  grep -qxF "$setting" "$config" || {
    printf 'checked-in configuration violates policy: %s\n' "$setting" >&2
    exit 1
  }
done <"$policy"

if command -v sha256sum >/dev/null; then
  config_sha256="$(sha256sum "$config" | awk '{print $1}')"
else
  config_sha256="$(shasum -a 256 "$config" | awk '{print $1}')"
fi
grep -qF "$config_sha256" "${project_dir}/docs/kernel.md" || {
  printf 'kernel documentation has a stale config SHA-256: %s\n' \
    "$config_sha256" >&2
  exit 1
}

test "$(grep -c '@@KERNEL_IMAGE@@' "${project_dir}/lima/fedora-x86.yaml.in")" -eq 1
test "$(grep -c '@@KERNEL_SHA256@@' "${project_dir}/lima/fedora-x86.yaml.in")" -eq 1
# Match the literal template variable, not this test process's environment.
# shellcheck disable=SC2016
test "$(
  grep -c -F \
    'BindReadOnly=${cpuinfo_path}:/mnt/lima-cpuinfo' \
    "${project_dir}/lima/fedora-x86.yaml.in"
)" -eq 1
grep -qF 'rosetta-cpuinfo.service' \
  "${project_dir}/lima/fedora-x86.yaml.in"
grep -qF 'proc-cpuinfo.mount' \
  "${project_dir}/lima/fedora-x86.yaml.in"
grep -qF 'rosetta-cpuinfo-validate' \
  "${project_dir}/lima/fedora-x86.yaml.in"
grep -qF 'rosetta-cpuinfo-check' \
  "${project_dir}/lima/verify-runtime.sh"

if grep -R -n -F "$HOME" "$project_dir"; then
  printf 'found a machine-specific path\n' >&2
  exit 1
fi

git -C "$source_dir" diff --check -- \
  . \
  ':(exclude)lima-rosetta/kernel/patches/*.patch'
git -C "$source_dir" apply --reverse --check \
  "${project_dir}/kernel/patches/"*.patch

printf 'static checks passed\n'
