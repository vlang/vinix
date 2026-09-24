# AArch64 QEMU sound regression

This test boots a freshly built Vinix kernel with a static test program as PID
1 and a VirtIO sound card whose output QEMU records to a WAV file. The guest
opens `/dev/dsp` the way SDL's OSS backend does and plays 2 s of a 440 Hz tone
at 44.1 kHz stereo. A child process then starts a 660 Hz tone and is killed
part-way through it, and the device is reopened for 0.5 s of 880 Hz at
22.05 kHz mono. It checks the OSS parameter ioctls, that a second opener gets
EBUSY while the first has the device, that the writes block for about as long
as the audio lasts, that a signal with a handler arriving every 5 ms never cuts
a write short, and that a process blocked in a long write dies promptly on
SIGKILL and leaves the device free.

The host then reads the recording and checks the pitch and length of each
tone and that the sound has no dropouts.

Build the AArch64 userland once to provide the musl test sysroot, then run:

```sh
./build-userland-aarch64.sh
tests/sound/run.sh
```

Set `VINIX_SOUND_NO_BUILD=1` to reuse `kernel/bin/vinix`,
`VINIX_SOUND_ROOT` to boot another checkout's kernel and runner,
`VINIX_SOUND_KEEP=1` to keep the VM state and recording, or
`VINIX_QEMU_TIMEOUT` to change the default 300-second deadline.
