#!/usr/bin/env bash
# Source-only test port reservation helpers. No public environment interface.
# reserve_test_port ROOT OWNER [BASE] reserves one 100-port range, 60100..60899.
# ROOT must be shared by parallel WSL runs (the common evidence root).
# OWNER is the unique run directory. Sets port and port_lease in the caller.
# release_test_port OWNER releases only this caller's verified reservation.
reserve_test_port() {
    local root="$1" owner="$2" requested="${3:-}" candidate rows
    local -a candidates=()
    port_lease=""
    mkdir -p -- "$root" || return 1
    [[ ! -L "$root" ]] || return 1
    if [[ -n "$requested" ]]; then
        [[ "$requested" =~ ^60[1-8]00$ ]] || return 2
        candidates=("$requested")
    else
        mapfile -t candidates < <(shuf -i 601-608)
        candidates=("${candidates[@]/%/00}")
    fi
    for candidate in "${candidates[@]}"; do
        # mkdir is the atomic arbiter across WSL distributions sharing DrvFS.
        mkdir -- "$root/$candidate" 2>/dev/null || continue
        port_lease="$root/$candidate"
        if ! printf '%s\n' "$owner" >"$port_lease/owner"; then
            rmdir -- "$port_lease" 2>/dev/null || true
            port_lease=""; return 1
        fi
        if ! rows="$(ss -H -ltn)"; then
            release_test_port "$owner" || true
            return 1
        fi
        if awk -v lo="$candidate" -v hi="$((candidate+99))" \
            '{n=split($4,a,":"); if(a[n]>=lo && a[n]<=hi) busy=1} END {exit busy}' <<<"$rows"; then
            port="$candidate"
            return 0
        fi
        release_test_port "$owner" || return 1
    done
    printf 'Нет свободного тестового диапазона портов (60100..60899).\n' >&2
    return 1
}

release_test_port() {
    [[ -n "${port_lease:-}" ]] || return 0
    [[ ! -L "$port_lease" && ! -L "$port_lease/owner" && "$(cat "$port_lease/owner")" == "$1" ]] || return 1
    rm -- "$port_lease/owner" || return 1
    rmdir -- "$port_lease" || return 1
    port_lease=""
}
