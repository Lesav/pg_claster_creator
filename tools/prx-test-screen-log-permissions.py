#!/usr/bin/env python3
# Purpose: test screen TTY policy and cold-restore log permissions in isolated fixtures.
# Usage: python3 tools/prx-test-screen-log-permissions.py REPO LOG_DIR
# Args: REPO -- source tree; LOG_DIR -- new evidence directory.
# Output: per-case logs/results; no real clusters, packages or shared directories changed.
# Example: python3 tools/prx-test-screen-log-permissions.py /repo /repo/tmp/fix-check
import errno
import os
import pathlib
import pty
import select
import subprocess
import sys
import tempfile
import time

repo, logs = map(pathlib.Path, sys.argv[1:])
logs.mkdir(parents=True, exist_ok=False)
source = 'source "$1/create-claster.sh"\n'
results = []

def case(name, body, tty=False, term='xterm', expected=0, marker=None):
    env = os.environ.copy()
    if term is None:
        env.pop('TERM', None)
    else:
        env['TERM'] = term
    started = time.time()
    args = ['bash', '-c', source + body, 'fixture', str(repo)]
    if tty:
        master, slave = pty.openpty()
        proc = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        output = bytearray()
        try:
            while True:
                if time.time() - started > 30:
                    proc.kill()
                    raise RuntimeError('PTY timeout')
                if select.select([master], [], [], 0.2)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
            rc = proc.wait(timeout=5)
        finally:
            os.close(master)
            if proc.poll() is None:
                proc.kill()
                proc.wait()
        output = bytes(output)
    elif name == 'screen-file':
        with (logs / (name + '.log')).open('wb') as stream:
            rc = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=stream, stderr=stream, env=env, timeout=30).returncode
        output = (logs / (name + '.log')).read_bytes()
    else:
        completed = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, timeout=30)
        rc, output = completed.returncode, completed.stdout
    (logs / (name + '.log')).write_bytes(output)
    ok = rc == expected and (marker is None or marker in output)
    if name.startswith('screen-'):
        wants_escape = tty and term == 'xterm' and name != 'screen-warning'
        ok = ok and ((b'\x1b' in output) == wants_escape)
    results.append('{}\t{}\trc={} seconds={:.3f}\n'.format(name, 'PASS' if ok else 'FAIL', rc, time.time()-started))

for name, tty, term in [('file', False, 'xterm'), ('pipe', False, 'xterm'),
                        ('pty', True, 'xterm'), ('empty', True, ''),
                        ('unset', True, None), ('dumb', True, 'dumb'), ('unknown', True, 'unknown')]:
    case('screen-'+name, 'NON_INTERACTIVE=0; header; clear_screen; printf "VISIBLE\\n"', tty, term, marker=b'VISIBLE')
case('screen-warning', 'NON_INTERACTIVE=0; STARTUP_PREPARATION=1; warn KEEP; header; [[ "$PRESERVE_NEXT_CLEAR" == 0 ]]', True, marker=b'KEEP')
case('screen-main', 'NON_INTERACTIVE=0; SELECTED_PACKAGE=fixture; main_menu <<<0', marker=b'fixture')
case('screen-info', 'NON_INTERACTIVE=0; cluster_rows() { printf "18 qa 55432 down postgres /absent /absent.log\\n"; }; info_menu <<< $\'1\\n0\\n0\'', marker=b'down')

with tempfile.TemporaryDirectory(prefix='pgcc-log-perms-') as directory:
    fixture = pathlib.Path(directory)
    # Only the constant path in this one function is redirected. Its mkdir/chown/
    # chmod commands operate on a real Linux filesystem and use the real postgres group.
    remap = 'definition="$(declare -f restore_log_directory_permissions)"; eval "${definition//\/var\/log\/postgresql/$FIXTURE/logs}"\n'
    previous = os.environ.get('FIXTURE')
    os.environ['FIXTURE'] = directory
    try:
        body = remap + '''
mkdir "$FIXTURE/logs"
touch "$FIXTURE/logs/existing.log"
chmod 640 "$FIXTURE/logs/existing.log"
before="$(stat -c '%u:%g:%a' "$FIXTURE/logs/existing.log")"
chown root:root "$FIXTURE/logs"; chmod 755 "$FIXTURE/logs"
restore_log_directory_permissions
[[ "$(stat -c '%U:%G:%a' "$FIXTURE/logs")" == root:postgres:1775 ]]
[[ "$(stat -c '%u:%g:%a' "$FIXTURE/logs/existing.log")" == "$before" ]]
runuser -u postgres -- test -w "$FIXTURE/logs"
'''
        # postgres must be able to traverse the fixture parent for test -w.
        fixture.chmod(0o755)
        case('log-real-permissions', body)
        for command in ['mkdir', 'chown', 'chmod']:
            case('log-fail-'+command, remap + command + '() { return 1; }; restore_log_directory_permissions; echo UNREACHABLE', expected=1, marker='ОШИБКА'.encode())
        case('log-symlink', remap + 'mv "$FIXTURE/logs" "$FIXTURE/target"; ln -s target "$FIXTURE/logs"; restore_log_directory_permissions', expected=1, marker='символьной ссылкой'.encode())
        case('legacy-members-metadata', '''
work="$FIXTURE"; logs="$FIXTURE/evidence"; mkdir "$logs"
eval "$(sed -n '/^make_legacy()/,/^}/p' "$1/tools/prx-test-live-edges.sh")"
mkdir -p "$work/tree/root/etc/postgresql/18/qa" "$work/tree/root/usr/lib/systemd/system"
touch "$work/tree/root/etc/postgresql/18/qa/postgresql.conf" "$work/tree/root/usr/lib/systemd/system/postgresql@18-qa.service"
chmod 700 "$work/tree/root/etc/postgresql/18/qa"
cold="$work/original.tar.gz"; legacy="$work/legacy.tar.gz"
tar -czf "$cold" -C "$work/tree" root/etc/postgresql/18/qa root/usr/lib/systemd/system/postgresql@18-qa.service
original_sha="$(sha256sum "$cold")"
make_legacy
[[ "$(sha256sum "$cold")" == "$original_sha" ]]
! tar -tzf "$legacy" | grep -q '\\.service$'
tar -czf "$work/bad.tar.gz" -C "$work/tree" root
cold="$work/bad.tar.gz"
if make_legacy; then echo 'unsafe archive accepted'; exit 1; fi
echo 'PASS original members/metadata preserved; unsafe parent-tree archive refused'
''', marker=b'PASS original members')
    finally:
        if previous is None:
            os.environ.pop('FIXTURE', None)
        else:
            os.environ['FIXTURE'] = previous

# Assert integration ordering: extraction -> permission repair -> cluster start.
code = (repo / 'create-claster.sh').read_text(encoding='utf-8')
cold = code.split('restore_menu() {', 1)[1].split('\ninfo_menu() {', 1)[0]
assert cold.index('--keep-directory-symlink') < cold.index('\n    restore_log_directory_permissions\n') < cold.index('start_cluster_checked')
assert code.count('clear 2>/dev/null') == 1
(logs / 'results.tsv').write_text(''.join(results), encoding='utf-8')
print(''.join(results), end='')
sys.exit(any('\tFAIL\t' in row for row in results))
