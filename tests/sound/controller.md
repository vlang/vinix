The sound supervisor is `tests/native-system-tools/systemhost/sound.v`.
`run_vm` compiles it directly with the selected host V compiler. It owns QEMU's
private process group and PTY, captures the guest transcript, and preserves the
300-second deadline, marker stop, final drain and orderly shutdown.

V also parses the recorded WAV, estimates tone frequency from interpolated
zero crossings and checks the original tone order, durations and dropouts.
The guest C workload and its assertions remain unchanged. `run.sh` retains its
existing fixture/kernel build options and invokes this native supervisor.

`check-devices.v` supplies independent mono/stereo WAV controls, including an
unfinished data header, silence and wrong tone order. `check-devices-cli.v`
checks the complete command path with controlled serial and audio outputs.
Real QEMU recording is qualified separately; host tone controls do not prove
physical audio playback. The older `soundcore` query files are historical
bridge sources and are no longer part of the maintained command path.
