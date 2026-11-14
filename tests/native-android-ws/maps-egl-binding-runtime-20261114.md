# Maps adapter binding failure and job builder exit

Fresh r79 used the unchanged r78-qualified SDK/native/protocol/core/TLS bytes
with the controller rebuilt by available V 0.5.2 9a38ec5 and the paced runner
from b9744e077. It reached onboarding and Explore. The map remained uniformly
beige. No search, route or account authentication result is qualified here.

The private log records:

```text
ANDROID-WS-EGL-ERROR returned=0x300d adapter=0x300d provider=0x3000
```

The only adapter path setting 0x300d is the tracked-window swap guard in
ws_egl_swap: its requested display or draw surface differs from the calling
thread's current binding. Mesa's recorded error was EGL_SUCCESS. This narrows
the rendering investigation to that guard; it does not identify the mismatched
handle or prove why the binding changed. The guard agrees with the
[EGL 1.5 posting requirements, section 3.10.4](https://registry.khronos.org/EGL/specs/eglspec.1.5.pdf)
and remains intact. Removing it would not establish correct presentation.
The next diagnostic records lifecycle arguments/results and current bindings
on this rejection, without changing binding or error-return semantics.

Two logged EGL frames were uniform opaque beige 480x640. All three early
surface-state samples still had surfaceIsBad=false; K/L were null in the first
two and non-null in the third. The later EGL error was outside those limited
samples. These samples do not qualify a healthy renderer or a persistent
null-camera/viewport explanation.

Maps exited at 07:38:28 UTC with status 10 after a GMS coroutine's uncaught
NoSuchMethodError for JobInfo.Builder.setImportantWhileForeground(boolean).
The call was on DefaultDispatcher-worker-3. No bounded notification transport
failure marker was emitted in this attempt. Activity-recognition permission
denials and other caught exceptions remain in the complete log; they were not
reclassified as permissions to grant or as proven causes of this exit.
The next SDK repair and signed probe address the missing job API.

The latest controller passed host self-tests and static ARM build under the
original explicit caps: 41040 ms, peak sampled RSS 521355264 bytes, shared growth
179470336 bytes, exit 0/0, cleanup complete. Its SHA256 is
20ae10b256d2d297607e464d48fc7edc8bafc717e32ef00205ef4b4838db2692.
Fresh r79 staging also passed: 15548 ms, RSS 37732352 bytes, growth 182943744
bytes, exit 0/0, cleanup complete. Both retained RSS 629145600 bytes, wall
300000 ms, reserve 1073741824 bytes, growth 536870912 bytes and output 4194304
bytes. Disk UUID 1465bfcbbf1243c28548ceb2c390cfa7 passed identity inspection,
read-only e2fsck and initial hash checks before launch. Resources remain
12 GiB/four CPUs.

The controller also passed its actual ARM self-tests, including 256-iteration,
64-process scratch-memory checks. Snapshot latest-controller-selftest-uart-20261114-r1
full SHA256 5676d71f4d928798d10f7cde157b744e150465fb6e454428862901ee3176bf6e;
receipt fb23a332e9d8a2859bbbfa97034892947484569b1d95abf1a060b68dde623ace.
No repeated full API run is claimed for r79: SDK/native bytes were unchanged
from r78, and the new controller was separately tested on ARM.

The 600052 ms watch completed with minimum guest free space 7246426112 bytes
and available memory 4635248 KiB. The broker continued to its existing deadline
and reported bounded-session-ended-no-authentication-claim. Its complete UART
export BEGIN/END digest is
4e0d822837c40a1932d4adff487aa0bd807a4df143f8820e1c36896b1d6496a8
(1427808 bytes/2789 chunks); no strict-import pass is claimed. After export,
sync returned to an actual prompt. Owned QEMU PID 55073 was stopped and verified
absent before offline extraction. No test VM from this run remains running.

Complete evidence remains in
`/Users/alex/.local/state/vinix/android/maps-current-20261114-r79/`:

| Artifact | SHA256 |
| --- | --- |
| maps.retained.log | 5f93a2d41ef283356dda97da738d4206c6bd7b7e68a32e21fbce05f308d9674c |
| broker.retained.log | 581bf2ddbe74f3101c879243ab18edb842331e9017cac1e2de1bceb54cb45c60 |
| receipt.retained.json | d29bc76f9f65cd332042a09a02dcaa622b9259ae3cf3138bec559c16523bc283 |
| maps-launch.retained.json | 677eae7436cb63fb834076a8cbe99a73041211b8db117b2b2883f41f5a5fe28b |
| serial.log | 12fc0661141203caa50a352e133a280e8ded4dde829255aa70159af7b104adb1 |
| final app-data.ext2 | 7ef6fa750461d53a6bfaa5a9f3652e2de6ffaab554f694ba3dd5b4cc0a33fe74 |
