# Maps EGL and notification failure diagnostics

r76's protected renderer capture records a bad EGL surface after its first
uniform frame and a later fatal notification cancellation transport failure.
See [the retained ARM results](maps-renderer-fields-20261113.md). The exact EGL
failure and transport errno were not observable in that build.

The native adapter now logs the EGL error already consumed by eglGetError,
including its adapter/provider components. It makes no additional EGL query
and preserves error precedence, clearing and the returned value. This trace
requires the existing protected tree-diagnostic selection and emits at most
32 failures per process. Unexpected notification transport failures now emit
at most 16 stage/error records per process. Immediate syscall failures retain
their errno; unclassified failures use -1. Existing absent-broker cancellation
semantics, transport classification and exceptions remain unchanged. These are
diagnostics, not a rendering or notification transport repair.

The signed API fixture now cancels a never-posted ID twice under its isolated
identity without a notification broker. It queues a main-handler fence after
both cancellations, so its pass marker follows their actual queued work.
ARM execution of this new regression is pending.

Sources are the nativews diagnostics/egl_state/notifications files and
current-api-fixture plus notificationcancelprobe in this commit, following
controller a4e654561. All generated evidence remains under
`/Users/alex/.local/state/vinix/android/`. Builds used the available V 0.5.2
6f888d6 executable at `/Users/alex/code/v/v`, SHA256
5bb15e45aebb0c174abb4b8c962d6bcb2633aee2f63d5d6f30247becffeb191b.
No compiler revision pin was introduced.

Every following completed build explicitly retained the original caps: RSS
629145600 bytes, wall 300000 ms, reserve 1073741824 bytes, growth 536870912
bytes and output 4194304 bytes. All returned exit 0/0 with complete cleanup.

| External build | Result |
| --- | --- |
| current-native-egl-notice-trace-20261113-r1 | Native generation, ABI checks and AArch64 link passed; 10036 ms, peak sampled RSS 472481792, growth 8347648 bytes |
| notice-cancel-fixture-tool-20261113-r1 | Producer compilation passed; 1629 ms, peak sampled RSS 376356864, growth 2256896 bytes |
| current-api-notice-cancel-20261113-r1 | APK generation and v3 signature verification passed; 1040 ms, peak sampled RSS 109625344, growth 782336 bytes |

The native library SHA256 is
fd313aa1ebf4bcff5218bfeebf9046999cfcc2718b02a770ba98e679d96e2db8;
the signed probe.apk SHA256 is
f878a3b89ee7b1c8c78a79898232c890cfc6ab5a8e76d6c9213af86df4e6f862.
Native generated inputs remain in its tools/native directories; the fixture
producer inputs remain in notice-cancel-inputs-20261113-r1. The corresponding
external .guard.json files retain commands, limits and measured results.

| Guard receipt | SHA256 |
| --- | --- |
| Native build | 134133d4f673c9e4d08e4023e6797a722ce71ab885151ad5901d4ec6adf79776 |
| Fixture producer compilation | d8d5c96bf5c43560a72e2a5019020e86d5e93d4fba3212f702481c1aa682ff2c |
| Signed fixture generation | 1b7262cc7b27ef9958b9eee8c6210da04321d0477f1e0ecd4f7b6b14ff2d49cb |
| r77 staging refusal | 27570943e7c1966312fa56ed3d0bbc0abf30a951cfdcee45ce00fe246392a0ee |

The fresh r77 VM staging guard refused before starting a child (PID 0,
child exit -1): only 1201610752 bytes were free, below reserve plus growth.
Its retained maps-current-20261113-r77.stage.guard.json is a refusal, not a
staging or cleanup pass. Subsequent read-only probes saw less than 1 GiB free.
No r77 VM was launched; all test VMs started by this continuation are stopped.
The new native diagnostics and cancellation regression have not passed ARM
runtime validation. Existing r75 API results do not qualify these new bytes.

A separate unproved rendering lead is shared EGL display lifetime:
ws_egl_initialize forwards every initialization to Mesa and ws_egl_terminate
immediately tears down display windows, whereas Android's EGL implementation
[reference-counts display initialization](https://android.googlesource.com/platform/frameworks/native/+/be3c3e4/opengl/libs/EGL/egl_display.cpp).
A balanced initialize/terminate on another thread should be tested while a
renderer retains its display. No lifetime change has been made, and this has
not been established as the cause of the Maps failure.

Next: restore host space, stage a fresh guest with this native library and
signed fixture under the same caps, run the complete signed ARM regression,
then repeat the protected Maps trace to identify the actual EGL error and
notification failure stage. Tiles, route geometry and sign-in remain pending.
