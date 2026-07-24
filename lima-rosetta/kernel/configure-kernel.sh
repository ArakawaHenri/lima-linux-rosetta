#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu

src=${1:?usage: configure-kernel.sh SOURCE OUTPUT APPLE_CONFIG}
out=${2:?usage: configure-kernel.sh SOURCE OUTPUT APPLE_CONFIG}
base=${3:?usage: configure-kernel.sh SOURCE OUTPUT APPLE_CONFIG}
script_dir=$(CDPATH='' cd -P "$(dirname "$0")" && pwd)
policy=$script_dir/config-policy-6.18.39-rosetta-tso-lto

mkdir -p "$out"
cp "$base" "$out/.config"

# First migrate Apple's VZ/container kernel baseline to Linux 6.18.39 and to
# the active LLVM toolchain. Then apply the explicit project policy and resolve
# dependencies one more time.
make -C "$src" ARCH=arm64 LLVM=1 O="$out" olddefconfig

cfg=$src/scripts/config
config=$out/.config

apply_setting()
{
    setting=$1
    case "$setting" in
        CONFIG_*=y)
            symbol=${setting#CONFIG_}
            symbol=${symbol%=y}
            "$cfg" --file "$config" --enable "$symbol"
            ;;
        '# CONFIG_'*' is not set')
            symbol=${setting#\# CONFIG_}
            symbol=${symbol% is not set}
            "$cfg" --file "$config" --disable "$symbol"
            ;;
        CONFIG_*=\"*\")
            symbol=${setting%%=*}
            symbol=${symbol#CONFIG_}
            value=${setting#*=}
            value=${value#\"}
            value=${value%\"}
            "$cfg" --file "$config" --set-str "$symbol" "$value"
            ;;
        CONFIG_*=*)
            symbol=${setting%%=*}
            symbol=${symbol#CONFIG_}
            value=${setting#*=}
            "$cfg" --file "$config" --set-val "$symbol" "$value"
            ;;
        *)
            printf 'invalid policy setting: %s\n' "$setting" >&2
            exit 1
            ;;
    esac
}

while IFS= read -r setting || [ -n "$setting" ]; do
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
    apply_setting "$setting"
done <"$policy"

make -C "$src" ARCH=arm64 LLVM=1 O="$out" olddefconfig

# The policy is both the configuration input and the resolved-output contract.
# Exact-line checks distinguish an unavailable symbol from a disabled one and
# make Kconfig dependency changes fail the build instead of silently drifting.
while IFS= read -r setting || [ -n "$setting" ]; do
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
    if ! grep -qxF "$setting" "$config"; then
        printf 'resolved configuration violates policy: %s\n' "$setting" >&2
        exit 1
    fi
done <"$policy"

printf 'configured %s\n' "$config"
