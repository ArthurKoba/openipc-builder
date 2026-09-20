#!/bin/sh
# GARUS GSL-5030X-30AP-NM / BLK16EV2-4339P-38X38, Hi3516EV200 only.
# S30customizer executes this hook on EVERY boot, outside the custom.ok guard.
# Run before S70vendor/S95majestic; do not use the network-fetched ipctool plugin.
set -eu

fail() {
    echo "garus muxes: $*" >&2
    exit 1
}

[ "$(ipcinfo -c)" = "hi3516ev200" ] || fail "unexpected SoC; no GPIO writes"
command -v devmem >/dev/null 2>&1 || fail "devmem is unavailable"

read_reg() {
    value=$(devmem "$1" 32) || fail "cannot read $1"
    case "$value" in
        0x*) digits=${value#0x} ;;
        *) fail "invalid register value at $1" ;;
    esac
    case "$digits" in
        ''|*[!0-9a-fA-F]*) fail "invalid register value at $1" ;;
    esac
    [ "${#digits}" -le 8 ] || fail "register value exceeds 32 bits at $1"
    printf '%s\n' "$value"
}

update_bits() {
    reg=$1 mask=$2 bits=$3
    old=$(read_reg "$reg") || exit 1
    new=$(( (old & ~mask) | (bits & mask) ))
    if [ "$((old))" -ne "$new" ]; then
        devmem "$reg" 32 "$(printf '0x%08x' "$new")" || fail "cannot write $reg"
    fi
    actual=$(read_reg "$reg") || exit 1
    [ "$((actual & mask))" -eq "$((bits & mask))" ] || fail "readback failed at $reg"
}

# First make GPIO1_7 an input, so selecting its pad cannot drive against the
# external status transistor. Preserve all other directions in bank 1.
update_bits 0x120B1400 0x80 0x00

# EV200 pad at 0x120C001C: selector 2 = GPIO1_7, low-nibble mask 0x0f.
# Preserve pull/drive/slew bits. GPIO8/9 are already GPIOs on the tested board;
# their output levels and short IR-cut pulses remain owned by Majestic.
update_bits 0x120C001C 0x0f 0x02
