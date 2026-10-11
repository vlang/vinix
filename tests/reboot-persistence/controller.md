The reboot command and fixture build are native V in
[`diskhost/reboot.v`](../native-disk-tools/diskhost/reboot.v). Archive preparation,
private kernel snapshots and disk seeds no longer use a Python object bridge.
The shared native PTY owner keeps one QEMU process through both guest boots.

The final verdict retains two START and SYNCING brackets, the write marker,
PASS and rejection of every original failure marker. Cleanup retains the
monitor request, five-second initial wait and TERM/KILL phases. See
[qualification and limits](../native-disk-tools/README.md).
