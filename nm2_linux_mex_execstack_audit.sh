#!/usr/bin/env bash
# External distribution-maintenance utility; not part of the NM2 source tree.
# Usage: bash nm2_linux_mex_execstack_audit.sh --check /path/to/NM2
#        bash nm2_linux_mex_execstack_audit.sh --fix /path/to/NM2
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != '--check' && "$1" != '--fix' ) || ! -d "$2" ]]; then
    echo 'Usage: bash nm2_linux_mex_execstack_audit.sh --check|--fix /path/to/NM2' >&2
    exit 2
fi
mode=$1
root=$2
command -v readelf >/dev/null || { echo 'Missing readelf (binutils)' >&2; exit 2; }
if [[ $mode == '--fix' ]]; then
    command -v patchelf >/dev/null || { echo 'Missing patchelf' >&2; exit 2; }
fi

count=0
flagged=0
fixed=0
unknown=0
while IFS= read -r -d '' f; do
    ((count+=1))
    flags=$(readelf -W -l -- "$f" | awk '$1 == "GNU_STACK" {print $7; exit}')
    if [[ -z $flags ]]; then
        echo "UNKNOWN (missing GNU_STACK): $f"
        ((unknown+=1))
        continue
    fi
    if [[ $flags != *E* ]]; then
        continue
    fi
    ((flagged+=1))
    echo "EXECUTABLE STACK: $f"
    if [[ $mode == '--fix' ]]; then
        backup="${f}.nm2-execstack-original"
        if [[ -e $backup ]]; then
            echo "Refusing to overwrite existing backup: $backup" >&2
            exit 2
        fi
        cp -p -- "$f" "$backup"
        if ! patchelf --clear-execstack "$f"; then
            cp -p -- "$backup" "$f"
            echo "Repair failed and original restored: $f" >&2
            exit 2
        fi
        flags_after=$(readelf -W -l -- "$f" | awk '$1 == "GNU_STACK" {print $7; exit}')
        if [[ -z $flags_after || $flags_after == *E* ]]; then
            cp -p -- "$backup" "$f"
            echo "Verification failed and original restored: $f" >&2
            exit 2
        fi
        ((fixed+=1))
        echo "  fixed; original retained as: $backup"
    fi
done < <(find "$root" -type f -name '*.mexa64' -print0)

printf 'Scanned: %d  Executable stack found: %d  Fixed: %d  Missing GNU_STACK: %d\n' \
       "$count" "$flagged" "$fixed" "$unknown"
if [[ $unknown -ne 0 ]]; then exit 2; fi
if [[ $mode == '--check' && $flagged -ne 0 ]]; then exit 1; fi
