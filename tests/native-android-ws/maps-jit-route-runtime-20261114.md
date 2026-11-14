# JIT and rendered Maps routes

This continuation follows 85bee16a6. ART JIT is enabled in the native bootstrap;
JNI checks, image compilation policy, trust, account authority, session deadlines
and all resource guards remain unchanged. Comparing the retained native source
trees against the qualified shared-display build finds only bootstrap.v changed
from -Xusejit:false to true. Actual Maps jit.cc messages confirm compilation.

Available V 0.5.2 9a38ec5, executable SHA256
f52821ef2d15507ef5238e36a5237c909dfbdbc09786671c5d87a3feb1ed843c,
built current-native-maps-jit-20261114-r1. Under the original explicit caps
(RSS 629145600, wall 300000 ms, reserve 1073741824, growth 536870912,
output 4194304), the build passed exit 0/0 with complete cleanup in 51146 ms,
peak sampled RSS 477249536 and shared growth 336785408 bytes. Generated C,
selected sources/headers, inputs.sha256, logs and guard receipt are retained.
Native DSO SHA256 is
005abd44f63f5932bada2a48e70f757f0078641a1a9384631137d25020d112cd.

Fresh r84 used the unchanged job-importance SDK, signed shared-display fixture,
latest qualified controller, paired expiry protocol/launcher and mandatory
core/TLS jars. Staging passed the same caps: 15365 ms, RSS 39485440, growth
163971072 bytes, exit 0/0, complete cleanup. UUID inspection
da88b3fc2c074c8abfb300e62c3d29f4, read-only e2fsck and initial hash passed.
The guest retained 12 GiB/four CPUs and its separate 8-GiB data image.

The complete signed ARM API regression passed as UID/GID 10160: ready/pass,
stdin closed, EOF drained, exit 0. EGL-SHARED-DISPLAY-PASS,
EGL-SHARED-TERMINATE-PASS, the original Java EGL checks, JOB-IMPORTANT-PASS
and CURRENT-API-PASS are retained. Diagnostic export reconstruction used its
zero-removal plan; this does not replace any historical strict auditor.

Actual Maps rendered North America and detailed Louvre buildings/streets,
returned place details/photos, and calculated an Eiffel Tower-to-Louvre drive
of eight minutes. The route overview now visibly renders the blue route,
alternate route and duration labels. Route preview renders the first mapped
segment and "Head toward Pont d'Iéna". Screenshots route-preview.png at
09:33:07 and turn-preview2.png at 09:33:52 UTC retain these observations.

Input still stalls. The search UP callback took 4137 ms, versus 14295 ms in
r82's interpreted trace. These are observations across different runs/host
loads, not a controlled JIT speedup measurement. The available host's one-minute
load dropped to 12.54 by 09:29; JIT alone is not established as the cause of the
improvement. Responsive use and Google authentication remain unqualified.

Closing Maps at 09:35 ended its app host. The existing protected controller
then failed closed with "Maps launch app host ancestry changed" at 09:35:08;
the subsequent desktop relaunch was refused. Preserve this as a failed session,
not a successful bounded stop or evidence of a new ART failure. No sign-in was
attempted. Neither private log contains a missing-method, fatal native signal,
ANDROID-WS-FAIL, numeric auth-pump failure or service-exit marker. The original
controller's single-launch and ancestry checks were not relaxed.

The 600183-ms storage watch retained at least 7243370496 guest disk bytes and
4161344 KiB available memory. Complete UART BEGIN/END agree on
262b897dbe01d77c48811f993accd283944756abb31d51f24dd31ff28bc3c3fc,
1428226 bytes and 2790 chunks. After sync returned to the actual prompt, owned
QEMU PID 85814 was stopped and confirmed absent before offline extraction.

All evidence remains under `/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA256 |
| --- | --- |
| maps-jit-api-uart-20261114-r1/full.log | d5687b4ab970bd7dd423f3e6e34d0c46d999f54575d7bb972fcac261b200af0e |
| UART snapshot receipt | 2b733607df373face3e64693ccde03f7d7c5aa97c90bf2e02bd918ea18abb5d1 |
| maps-jit-api-readback-20261114-r1/archive.json | 8dc033eced0ba283bd3a1416acb5ce28f6c1d886d53be107d251ed1479877cdb |
| maps-jit-api-child-20261114-r1/child.log | 07b67c7d8a01f73e92361c50757ae6713787c913a675e301bf83dd0b584c63f2 |
| maps-current-20261114-r84/maps.retained.log | 68f279d9b96659af9bead9f995f4893a5684b338655de8cb60456bd50272f288 |
| r84 broker.retained.log | 9cf1fd1e4eb8c07637620c1411bacb0a78b21636a58744d10795f52894cf07ff |
| r84 receipt.retained.json | f6590a8ffad9d35013036081be3ef039fd2e96829001a5db1d1ff9877a4257bb |
| r84 maps-launch.retained.json | 67dd2fa304c0dda2d4b25b0f70495d7facb64d9c3c4e4cd8ed4c8a9b1ff44885 |
| r84 final serial.log | ce0742dff6361b4341ea4f25bbbd8bf41203f8a59951797a1c1118d534d1c4c3 |
| r84 final app-data.ext2 | 74294c72663cffb9bdcea5efc19198c7fb8e89722ed4374bec43f178f8d15399 |
| r84 route-preview.png | 9fae562326e0b4e3075c090f385b9aaaad39aef610994440632ce094558aeadc |
| r84 turn-preview2.png | d4f62333265d0eefb080f44b4298473636f7dc92f0bf3bda6d6b201139110762 |
