#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

readonly kernel_version=6.18.39
readonly source_epoch=1784386418
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly script_dir
source_dir="$(cd -- "${script_dir}/../.." && pwd -P)"
readonly source_dir
readonly build_root="${1:-${script_dir}/build}"
readonly output_dir="${build_root}/out"
readonly artifact_dir="${build_root}/artifacts"
readonly jobs="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"

for command in make clang ld.lld sha256sum; do
  command -v "$command" >/dev/null || {
    printf 'missing build dependency: %s\n' "$command" >&2
    exit 1
  }
done

actual_version="$(make -s -C "$source_dir" kernelversion)"
if [[ "$actual_version" != "$kernel_version" ]]; then
  printf 'expected Linux %s, found %s\n' "$kernel_version" "$actual_version" >&2
  exit 1
fi

mkdir -p "$build_root" "$artifact_dir"

"${script_dir}/configure-kernel.sh" \
  "$source_dir" \
  "$output_dir" \
  "${script_dir}/apple-containerization-config-arm64"

export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-lima-rosetta}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-builder}"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$source_epoch}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-@${SOURCE_DATE_EPOCH}}"

make \
  -C "$source_dir" \
  ARCH=arm64 \
  LLVM=1 \
  O="$output_dir" \
  -j"$jobs" \
  Image

install -m 0644 \
  "$output_dir/arch/arm64/boot/Image" \
  "$artifact_dir/Image-6.18.39-rosetta-tso-lto"
install -m 0644 \
  "$output_dir/.config" \
  "$artifact_dir/config-6.18.39-rosetta-tso-lto"
install -m 0644 \
  "$output_dir/System.map" \
  "$artifact_dir/System.map-6.18.39-rosetta-tso-lto"

(
  cd "$artifact_dir"
  sha256sum \
    Image-6.18.39-rosetta-tso-lto \
    config-6.18.39-rosetta-tso-lto \
    System.map-6.18.39-rosetta-tso-lto \
    >SHA256SUMS
)

printf 'Built artifacts are in %s\n' "$artifact_dir"
