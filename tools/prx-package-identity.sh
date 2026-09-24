#!/usr/bin/env bash
# Source-only helper. Usage: approved_removal PACKAGE APPROVED_PACKAGE...
# Exact names win. Otherwise resolve installed identities using dpkg-query;
# never discard architecture qualifiers or accept an ambiguous bare package.
approved_removal() {
    local removed="$1" allowed inventory name arch state selected="" count=0 total=0
    shift
    for allowed in "$@"; do
        [[ "$removed" != "$allowed" ]] || return 0
    done
    [[ "$removed" =~ ^[a-z0-9][a-z0-9.+-]*(:[a-z0-9][a-z0-9-]*)?$ ]] || return 1
    inventory="$(dpkg-query -W -f='${Package}\t${Architecture}\t${db:Status-Status}\n')" || return 1
    while IFS=$'\t' read -r name arch state; do
        [[ "$state" == installed && "$name" == "${removed%%:*}" && -n "$arch" ]] || continue
        ((total += 1))
        [[ "$removed" != *:* || "$removed" == "$name:$arch" ]] || continue
        ((count += 1))
        selected="$name:$arch"
    done <<<"$inventory"
    ((count == 1)) || return 1
    for allowed in "$@"; do
        [[ "$allowed" != "$selected" ]] || return 0
        if [[ "$allowed" == "${selected%%:*}" && "$total" == 1 ]]; then return 0; fi
    done
    return 1
}
