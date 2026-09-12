#!/usr/bin/env bash
# Purpose: reinstall deployment packages after target removal with requested TCP ports occupied.
# Usage: tools/prx-test-live-regression.sh REPO DISTRO PG_VERSION PACKAGE FAMILY PORT RELEASE LOG_ROOT ports
# Args: sourced module; all parameters come from prx-test-live-regression.sh.
# Output: live-ports results; real port-conflict and stale marker checks.
# Example: see prx-test-live-regression.sh, append ports.
perl -MIO::Socket::INET -e '@s=map {IO::Socket::INET->new(LocalAddr=>"127.0.0.1",LocalPort=>$_,Listen=>1,ReuseAddr=>1) or die $!} @ARGV; $|=1; print "READY\n"; sleep 900;' "$((port+3))" "$((port+4))" "$((port+5))" >"$work/listener.log" 2>&1 &
listener=$!
for attempt in 1 2 3 4 5; do grep -q READY "$work/listener.log" && break; sleep 1; done
step LISTENERS 0 grep -q READY "$work/listener.log"
# Automatic replacement of occupied ports is specified for install modes 2/4.
for mode in 2 4; do
    target="${c}m$mode"; requested="$((port+mode+1))"
    deb="$(find "$core_work/debs" -name "*-$target-*.deb" -print -quit)"
    [[ -n "$deb" && ! -e "/etc/postgresql/$v/$target" ]]
    touch "$work/deployed-mode"
    step "OCCUPIED-INSTALL-$mode" 0 timeout -k 5 900 env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confold install -y --reinstall "$deb"
    actual="$(pg_lsclusters --no-header | awk -v n="$target" '$2==n {print $3}')"
    step "PORT-CHANGED-$mode" 0 test "$actual" != "$requested"
    step "PORT-READY-$mode" 0 pg_isready -h 127.0.0.1 -p "$actual"
    step "PORT-WARNING-$mode" 0 grep -F "$requested" "$logs/OCCUPIED-INSTALL-$mode.log"
done
kill "$listener"; wait "$listener" || true; listener=""
