#!/usr/bin/env python3
"""Private v5 state sampler; two serial disposable common-profile boots."""
from pathlib import Path
import datetime, hashlib, json, os, shutil, subprocess, tarfile, time, traceback

STATE = Path(__file__).resolve().parent
ROOT = STATE.parent.parent
SYSROOT = ROOT / 'third_party/useralloc-libc/build/useralloc/optimized-v5-final'
KERNEL = ROOT / 'build/useralloc-kernel-speed-v5/x86_64/vinix-x86_64'
QEMU = Path(shutil.which('qemu-system-x86_64')).resolve()
FIRMWARE = QEMU.parent.parent / 'share/qemu/edk2-x86_64-code.fd'
MACHINE = 'q35,vmport=off'
ACCEL = 'tcg,thread=single,tb-size=1024'
CPU = 'Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt'
SMP = '2,sockets=1,cores=2,threads=1'
EXPECTED = {
    KERNEL: '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74',
    SYSROOT / 'lib/ld-musl-x86_64.so.1': '6cf9e5ead03671c57dc0661e0fc02a675a34a5cf57826a09452001ded8932b03',
    SYSROOT / 'usr/lib/libc.a': 'eb50810aa7d3583f6469e23fce4c2f464a86197cfb2a0cdf5293b75baaedd90c',
    STATE / 'bench.c': 'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9',
}

def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    temp.replace(path)

checkpoint = {'started_utc': utc(), 'driver_pid': os.getpid(), 'stage': 'verify-inputs', 'boots': []}
def update(stage):
    checkpoint['stage'] = stage
    checkpoint['updated_utc'] = utc()
    save(STATE / 'checkpoint.json', checkpoint)

def boot(ordinal):
    update('prepare-boot-' + str(ordinal))
    for path, expected in EXPECTED.items():
        if sha(path) != expected: raise RuntimeError('Frozen input changed: ' + str(path))
    directory = STATE / ('boot-' + str(ordinal))
    directory.mkdir(exist_ok=False)
    record = {'ordinal': ordinal, 'state_dir': str(directory), 'started_utc': utc(), 'status': 'preparing'}
    checkpoint['boots'].append(record)
    update('copy-rootfs-' + str(ordinal))
    rootfs = directory / 'rootfs'
    shutil.copytree(SYSROOT, rootfs, symlinks=True)
    for name in ['dev', 'proc', 'sys', 'tmp', 'root', 'sbin']: (rootfs / name).mkdir(exist_ok=True)
    (rootfs / 'tmp').chmod(0o1777)
    for mode in ['dynamic', 'static']:
        shutil.copyfile(STATE / ('sampler-' + mode), rootfs / 'root' / ('sampler-' + mode))
        (rootfs / 'root' / ('sampler-' + mode)).chmod(0o755)
    init = rootfs / 'sbin/init'
    init.unlink(missing_ok=True)
    init.write_text('''#!/bin/sh
exec >/dev/com1 2>&1
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
mount -t proc proc /proc
echo DIAG-GUEST-BEGIN
for invocation in 1 2 3; do
    for mode in dynamic static; do
        echo DIAG-EXEC-BEGIN invocation=$invocation linkage=$mode
        /root/sampler-$mode
        status=$?
        echo DIAG-EXEC-END invocation=$invocation linkage=$mode exit_code=$status
        if [ "$status" != 0 ]; then
            echo DIAG-FAIL
            while :; do sleep 60; done
        fi
    done
done
echo DIAG-GUEST-DONE
while :; do sleep 60; done
''')
    init.chmod(0o755)
    initramfs = directory / 'initramfs.tar'
    with tarfile.open(initramfs, 'w', format=tarfile.USTAR_FORMAT) as archive: archive.add(rootfs, arcname='.')
    iso = directory / 'vinix.iso'
    env = dict(os.environ, VINIX_AMD64_ISO_BUILD_DIR=str(directory / 'iso-build'),
               VINIX_AMD64_KERNEL=str(KERNEL), VINIX_AMD64_INITRAMFS=str(initramfs), VINIX_AMD64_ISO=str(iso))
    update('build-iso-' + str(ordinal))
    with (directory / 'image-build.log').open('wb') as log:
        subprocess.run([str(ROOT / 'build-support/build-amd64-iso.sh')], env=env, check=True, stdout=log, stderr=log)
        subprocess.run(['xorriso', '-osirrox', 'on', '-indev', str(iso), '-extract', '/boot/vinix', str(directory / 'boot-kernel')],
                       check=True, stdout=log, stderr=log)
    if sha(directory / 'boot-kernel') != EXPECTED[KERNEL]: raise RuntimeError('Embedded kernel changed')
    for path, expected in EXPECTED.items():
        if sha(path) != expected: raise RuntimeError('Frozen input changed during ISO build: ' + str(path))
    if sha(rootfs / 'lib/ld-musl-x86_64.so.1') != EXPECTED[SYSROOT / 'lib/ld-musl-x86_64.so.1']:
        raise RuntimeError('Copied loader changed')
    serial = directory / 'serial.log'
    argv = [str(QEMU), '-name', 'Vinix private hot v5 diagnostic ' + str(ordinal),
            '-machine', MACHINE, '-accel', ACCEL, '-cpu', CPU, '-smp', SMP, '-m', '4096',
            '-display', 'none', '-monitor', 'none', '-drive', 'if=pflash,format=raw,readonly=on,file=' + str(FIRMWARE),
            '-cdrom', str(iso), '-serial', 'file:' + str(serial), '-no-reboot']
    config = {'argv': argv, 'qemu_version': subprocess.check_output([str(QEMU), '--version'], text=True).splitlines()[0],
              'machine': MACHINE, 'accelerator': ACCEL, 'cpu': CPU, 'smp': SMP, 'memory_mb': 4096,
              'input_sha256': {str(path): sha(path) for path in EXPECTED},
              'sampler_sha256': sha(STATE / 'sampler.c'),
              'executables_sha256': {mode: sha(rootfs / 'root' / ('sampler-' + mode)) for mode in ['dynamic', 'static']},
              'kernel_verification': 'Extracted completed ISO kernel hash equals immutable v5 kernel.',
              'iterations': 200000, 'samples': 7, 'fresh_execs_per_mode': 3,
              'limits': 'Private state probes run outside unchanged hot loops. Cross GCC executable differs from canonical guest GCC executable. CPU time is kernel accounting, not host process time.'}
    save(directory / 'config.json', config)
    record['status'] = 'booting'
    with (directory / 'qemu.log').open('wb') as log:
        process = subprocess.Popen(argv, stdout=log, stderr=log)
        (directory / 'qemu.pid').write_text(str(process.pid) + '\n')
        record['qemu_pid'] = process.pid
        update('collect-boot-' + str(ordinal))
        try:
            deadline = time.monotonic() + 1800
            last_done = 0
            while time.monotonic() < deadline:
                output = serial.read_text(errors='replace') if serial.exists() else ''
                done = output.count('DIAG-SAMPLER-DONE')
                if done != last_done:
                    print(utc(), 'boot', ordinal, 'samplers-completed', done, flush=True)
                    record['samplers_completed'] = done
                    update('collect-boot-' + str(ordinal))
                    last_done = done
                if any(marker in output for marker in ['KERNEL PANIC', 'FATAL EXCEPTION', 'DIAG-FAIL', 'ALLOC-ERROR']):
                    raise RuntimeError('Guest failure in ' + str(serial))
                if 'DIAG-GUEST-DONE' in output:
                    if done != 6 or output.count('DIAG-HOT ') != 84 or output.count('exit_code=0') != 6:
                        raise RuntimeError('Incomplete diagnostic records in ' + str(serial))
                    record['status'] = 'complete'
                    record['finished_utc'] = utc()
                    record['raw_log_sha256'] = sha(serial)
                    update('finished-boot-' + str(ordinal))
                    return
                if process.poll() is not None: raise RuntimeError('Own QEMU exited: ' + str(process.returncode))
                time.sleep(0.25)
            raise RuntimeError('Guest diagnostic timeout')
        finally:
            if process.poll() is None:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
            record['qemu_exit_code'] = process.returncode
            record['qemu_stopped_utc'] = utc()
            update('own-qemu-stopped-' + str(ordinal))

exit_code = 1
update('started')
try:
    for ordinal in [1, 2]: boot(ordinal)
    update('complete')
    exit_code = 0
except BaseException as error:
    checkpoint['error'] = repr(error)
    update('failed')
    traceback.print_exc()
finally:
    save(STATE / 'driver.exit.json', {'exit_code': exit_code, 'finished_utc': utc(), 'checkpoint': str(STATE / 'checkpoint.json')})
raise SystemExit(exit_code)
