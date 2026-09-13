#!/usr/bin/env bash
# Path note: If /mnt/d/Ai/pg_claster_creator in the example does not match
# your filesystem, replace it with the actual project path before running.
# Purpose: test builder tmp ownership and EXIT cleanup without installing packages.
# Usage: bash tools/prx-test-deb-tmp-cleanup.sh REPO
# Args: REPO -- project source directory.
# Output: PASS for new/existing/nonempty tmp, failures and symlink protection.
# Example: bash tools/prx-test-deb-tmp-cleanup.sh /mnt/d/Ai/pg_claster_creator
set -Eeuo pipefail
repo="$(realpath "$1")"
fixture="$(mktemp -d /tmp/pgcc-tmp-cleanup.XXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
for scenario in new existing nonempty failure validation_failure foreign symlink; do
    case_dir="$fixture/$scenario"
    mkdir "$case_dir"
    sed '/^main "\$@"$/d' "$repo/create-claster-deb.sh" >"$case_dir/builder.sh"
    case "$scenario" in
        existing) mkdir "$case_dir/tmp" ;;
        nonempty) mkdir "$case_dir/tmp"; touch "$case_dir/tmp/keep" ;;
        symlink) mkdir "$case_dir/target"; touch "$case_dir/target/keep"; ln -s target "$case_dir/tmp" ;;
    esac
    status=0
    bash -c '
        source "$1/builder.sh"
        MODE=1
        if [[ "$2" == validation_failure ]]; then MODE=2; pg=invalid; fi
        validate_options
        BUILD_WORK_DIR="$(mktemp -d "$TMP_DIR/create-claster-deb.XXXXXX")"
        touch "$BUILD_WORK_DIR/private"
        [[ "$2" != foreign ]] || touch "$TMP_DIR/keep"
        [[ "$2" != failure ]] || exit 7
    ' _ "$case_dir" "$scenario" >"$case_dir/output" 2>&1 || status=$?
    case "$scenario" in
        new) [[ "$status" == 0 && ! -e "$case_dir/tmp" ]] ;;
        existing) [[ "$status" == 0 && -d "$case_dir/tmp" && -z "$(ls -A "$case_dir/tmp")" ]] ;;
        nonempty|foreign) [[ "$status" == 0 && -f "$case_dir/tmp/keep" && "$(ls -A "$case_dir/tmp")" == keep ]] ;;
        failure) [[ "$status" == 7 && ! -e "$case_dir/tmp" ]] ;;
        validation_failure) [[ "$status" == 1 && ! -e "$case_dir/tmp" ]] ;;
        symlink) [[ "$status" == 1 && -L "$case_dir/tmp" && -f "$case_dir/target/keep" ]] ;;
    esac
    printf 'PASS: %s\n' "$scenario"
done
bash -n "$repo/create-claster-deb.sh"
