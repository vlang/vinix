# Reproduce the private Catalina serial capture

This recipe preserves the serial workflow used for the Catalina captures. It
requires an unmounted private Catalina 10.15.7 image, its single-user OpenCore
image, the recorded firmware, a private FAT transfer image, QEMU 11.1.1,
`qemu-img`, `mcopy`, and the host's Apple development tools with MacOSX15.4 SDK.
Those licensed images and SDK binaries are external inputs. The exact measured
command line is in [argv.json](argv.json), the GCC/header archive fingerprints
are in [cached-inputs.json](cached-inputs.json), and the recorded dependency
locations are in [dependency-urls.json](dependency-urls.json).
The exact runtime [serial controller](control.py) and
[timing collector](measure-recorded.py) are preserved with fingerprints in
[source-snapshots.json](source-snapshots.json). The collector contains this
capture's paths and build fingerprints; a new capture must record its own
paths and verified inputs.

Use a new runtime directory, new mutable firmware variables, a private disk
overlay and a private copy of the transfer image. Keep the recorded machine,
accelerator, CPU, vCPU topology and memory unchanged. Remap only host paths and
host socket/port endpoints, and save the complete resulting argv. Pass the
argument list directly to `subprocess.Popen`; the SMC value and paths containing
spaces are not shell commands.

For example, from this directory, the following launches a fresh private clone
using the recorded argv. Choose unused host ports and an unused runtime path.

```python
from pathlib import Path
import json, re, shutil, subprocess

runtime = Path("/absolute/new-private-runtime")
runtime.mkdir(mode=0o700, parents=True, exist_ok=False)
argv = json.loads(Path("argv.json").read_text())
for i, value in enumerate(argv):
    if i and argv[i - 1] == "-drive":
        fields = value.split(",")
        file_field = next((x for x in fields if x.startswith("file=")), None)
        if file_field is None:
            continue
        source = Path(file_field[5:])
        target = None
        if "if=pflash" in fields and "readonly=on" not in fields:
            target = runtime / "OVMF_VARS.fd"
            shutil.copyfile(source, target)
        elif "id=MacHDD" in fields:
            target = runtime / "Catalina-overlay.qcow2"
            subprocess.run(["qemu-img", "create", "-f", "qcow2", "-F", "qcow2",
                            "-b", str(source.resolve()), str(target)], check=True)
        elif "id=BenchTransfer" in fields:
            target = runtime / "transfer-fat.raw"
            shutil.copyfile(source, target)
        if target is not None:
            argv[i] = ",".join("file=" + str(target) if x == file_field else x for x in fields)
    elif i and argv[i - 1] == "-qmp":
        argv[i] = f"unix:{runtime}/qmp.sock,server=on,wait=off"
    elif i and argv[i - 1] == "-serial":
        argv[i] = f"unix:{runtime}/serial.sock,server=on,wait=off"
    elif i and argv[i - 1] == "-vnc":
        argv[i] = "127.0.0.1:18"
    elif i and argv[i - 1] == "-netdev":
        argv[i] = re.sub(r"hostfwd=tcp:127\.0\.0\.1:[0-9]+-:22",
                         "hostfwd=tcp:127.0.0.1:22352-:22", value)
(runtime / "argv.json").write_text(json.dumps(argv, indent=2) + "\n")
shutil.copyfile("control.py", runtime / "control.py")
with (runtime / "qemu.log").open("wb") as log:
    process = subprocess.Popen(argv, stdout=log, stderr=log)
(runtime / "qemu.pid").write_text(str(process.pid) + "\n")
```

The recorded boot image uses `keepsyms=1 -s -v serial=3`, with SIP disabled in
the private clone. Its serial interface is an AF_UNIX server socket. Copy
[control.py](control.py) into the new runtime directory as `control.py`, then
run it after that runtime's serial socket exists:

```sh
python3 /absolute/private-runtime/control.py
```

Append complete command lines to `commands.txt`. The controller sends those
bytes and preserves
all received bytes in `console.log`. Its cursor file allows the controller to
resume without resending already submitted commands. Keep one controller
attached to this VM's serial socket.

## Prepare and compile inside the guest

Stage the pinned GNU GCC 14.3.0 toolchain under `opt/local`, the compatible
Darwin headers under `bench-sdk`, and the saved [bench.c](../bench.c) on the
private FAT image before boot. Identify the attached transfer device using
the guest's device list; it appeared as `/dev/disk0` in the recorded VM.
Submit these guest commands through `commands.txt`:

```sh
/sbin/mount -uw /
/sbin/mount -uw /System/Volumes/Data
/sbin/kextload /System/Library/Extensions/msdosfs.kext
mkdir -p /tmp/allocfat
/sbin/mount_msdos /dev/disk0 /tmp/allocfat
cp -R /tmp/allocfat/opt /tmp/opt
cp -R /tmp/allocfat/bench-sdk /tmp/bench-sdk
cp /tmp/allocfat/bench.c /tmp/bench.c
/usr/bin/uname -a
/usr/bin/shasum -a 256 /tmp/bench.c
DYLD_LIBRARY_PATH=/tmp/opt/local/lib /tmp/opt/local/bin/gcc-mp-14 --version
if DYLD_LIBRARY_PATH=/tmp/opt/local/lib /tmp/opt/local/bin/gcc-mp-14 -dM -E - </dev/null | grep __clang__; then
    echo ALLOC-FAIL stage=compiler-is-clang
    exit 1
fi
DYLD_LIBRARY_PATH=/tmp/opt/local/lib /tmp/opt/local/bin/gcc-mp-14 -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -mmacosx-version-min=10.15 -isysroot /tmp/bench-sdk -nostdinc -isystem /tmp/opt/local/lib/gcc14/gcc/x86_64-apple-darwin19/14.3.0/include -isystem /tmp/bench-sdk/usr/include -S /tmp/bench.c -o /tmp/bench-native-fresh.s
/usr/bin/shasum -a 256 /tmp/bench-native-fresh.s
cp /tmp/bench-native-fresh.s /tmp/allocfat/bench-native-fresh.s
sync
umount /tmp/allocfat
echo MACOS-CODEGEN-DONE
```

Require the printed source hash to match
[source-snapshots.json](../source-snapshots.json). Preserve the compiler output
and complete preparation transcript. The recorded fresh guest assembly hash
was `ff4f96b50b88ea1482866c7fed1bbc0750d46e47c0f984466332615439136bdd`.
For a reproduction, record the actual fresh hash rather than copying that
claim into new metadata.
The original [preparation transcript](preparation-serial.log) retains boot,
setup diagnostics, compiler output and hashes before timing. Its
[submitted commands](preparation-commands.txt) are preserved separately.
[Build provenance](build-provenance.json) records the measured compiler and
assembler steps; the retained host assembly and executable were re-hashed
when saving this evidence.

## Assemble and return the executable

After `MACOS-CODEGEN-DONE`, read the guest-generated assembly from the unmounted
private transfer image on the host. These host commands only assemble/link
GNU GCC's guest-generated assembly:

```sh
mcopy -i /absolute/private-transfer.raw ::/bench-native-fresh.s /absolute/private-runtime/bench-native-fresh.s
xcrun clang -target x86_64-apple-macos10.15 -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk /absolute/private-runtime/bench-native-fresh.s -o /absolute/private-runtime/alloc-bench-native
shasum -a 256 /absolute/private-runtime/bench-native-fresh.s /absolute/private-runtime/alloc-bench-native
mcopy -o -i /absolute/private-transfer.raw /absolute/private-runtime/alloc-bench-native ::/alloc-bench-native
```

Then remount the FAT device in the guest, copy the executable, unmount it and
confirm its hash matches the host file:

```sh
/sbin/mount_msdos /dev/disk0 /tmp/allocfat
cp /tmp/allocfat/alloc-bench-native /tmp/alloc-bench-native
chmod 755 /tmp/alloc-bench-native
/usr/bin/shasum -a 256 /tmp/alloc-bench-native
umount /tmp/allocfat
echo MACOS-USERALLOC-READY
```

Save a new `config.json` using the actual common QEMU options, complete argv,
guest compile command, host link argv, benchmark/assembly/executable hashes,
GCC version, SDK, transport, 200,000 iterations and seven samples. The measured
[Catalina manifest](../catalina-1/config.json) shows the field layout. Reuse of a
prior binary is supported only after confirming the fresh guest assembly is
identical to the retained assembly and the guest executable hash still matches.

## Collect one complete timing cohort

Record the current byte length of `console.log` into the new cohort's
`serial-offset.txt` before submitting this single command:

```sh
/tmp/alloc-bench-native --label macos --iterations 200000 --samples 7
```

Copy every console byte from that saved offset into the cohort's `serial.log`
until `ALLOC-DONE`. Preserve all `ALLOC-SAMPLE` lines, including outliers, along
with the complete metadata and results. Treat `ALLOC-ERROR`, `ALLOC-FAIL`, an
incomplete workload or a missing completion record as a failed collection.
The recorded collector allowed up to 3,600 seconds. After collection, validate
the log with the saved [strict validator](../compare.py).

The measurement controller resumes and pauses only this runtime's QMP socket:
`qmp_capabilities`, `cont` before measurement, and `stop` after completion or
timeout. Do not pause the guest during a valid timing cohort. A collector
restart can resume from `serial-offset.txt` while the original benchmark keeps
running; it must not launch another benchmark or discard the already captured
records. Preserve that recovery in the cohort metadata.

Run Vinix and Catalina timing jobs sequentially. Copy each accepted completed
capture to the corresponding numbered final directory, then run
[recompute.py](../recompute.py). Every numbered final cohort participates, and
both per-cohort and pooled parity booleans must be considered.
