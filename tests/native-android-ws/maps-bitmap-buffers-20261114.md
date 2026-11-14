# Maps bitmap buffer transfer, 2026-11-14

The r90 Maps imagery worker failed on the absent
`Bitmap.native_copy_to_buffer(JLjava/nio/Buffer;II)V` binding (retained in
[maps-framework-apk-cache-20261114.md](maps-framework-apk-cache-20261114.md)).
The adapter now copies the actual RGBA or padded ALPHA_8 storage into writable
ByteBuffer, ShortBuffer and IntBuffer destinations. It validates logical and
physical bounds, preserves bytes and advances the Java position in elements
only after success. Direct, primitive heap and heap byte-buffer views are
supported. Explicit DEX monitor guards pair copying with recycling, including
exception exits. Primitive storage is pinned only during memmove; the release
is the only JNI call while pinned. No pixel ownership is transferred.

Current V was V 0.5.2 cbfc1be at /Users/alex/code/v/v, executable SHA256
9bde2851cedea03c3e488b0793a356aeb90644d13cf49e10fae6bf5518fff000.
No historical compiler replay was used. External evidence root:
`/Users/alex/.local/state/vinix/android`.

All successful guards below retained RSS 629145600, wall 300000 ms,
reserve 1073741824, growth 536870912 and output 4194304 bytes, with exit/child
exit 0/0 and cleanup_complete true.

| Check | Evidence stem | Time ms | Peak sampled RSS | Observed growth |
| --- | --- | ---: | ---: | ---: |
| Production native code, canaries, pin/local-reference cleanup, direct/heap/views, invalid ranges, read-only, unsupported types, padding, overlapping storage; five compiled negative mutations | bitmap-checks-20261114-r5 | 6384 | 177160192 | 16224256 |
| Full SDK assembly and Bitmap DEX readback; six missing/duplicate declaration refusals | framework-bitmap-buffers-20261114-r2 | 3495 | 478642176 | 179867648 |
| Full current-source native producer, generated C and AArch64 GCC -Werror link | bitmap-native-20261114-r6 | 19717 | 583221248 | 109371392 |
| Signed fixture assembly/signature verification, shared-display profile | current-api-bitmap-buffers-20261114-r2 | 1100 | 163872768 | 53043200 |

The signed fixture adds nine direct/heap/view configurations, nonzero positions,
slices, neighboring canaries, raw pixel values, element advancement, ALPHA_8
padding and failure-position checks. Separate workers exercise copy/recycle
while another thread holds the bitmap monitor. ARM execution is required;
host mocks alone do not qualify ART behavior.

| Deployable artifact | SHA256 |
| --- | --- |
| framework-bitmap-buffers-20261114-r2/classes.dex | d24d67440b00494a5d8ef00ee71dd8836283369e09317b994c6afb1ef1c9cd3d |
| bitmap-native-20261114-r6/native/libvinix-android-native.so | 1e50148f2fc896fa77f2c1b765f5c64aa69d247127cb4bd67462a65ad9984705 |
| current-api-bitmap-buffers-20261114-r2/probe.apk | 9e143c27fb7425b336e4eb528302e3f5c5eda8d094247cf7af678ecc2619e662 |

Earlier attempts remain retained. The initial DEX locking form was withdrawn
before an API or protected account run in r91; owned QEMU41856 was stopped.
r92's signed fixture passed the existing graphics checks, then correctly
failed at a heap typed view with "Bitmap buffer has no accessible storage".
Inspection of the actual retained NIOAccess and ByteBufferAsShortBuffer /
ByteBufferAsIntBuffer DEX showed why public array access fails for these views.
The final adapter reads their immutable backing-buffer/offset fields and
checks both backing-buffer and array bounds. r92's full failed child log was
copied to the checked persistent volume and synced before stopping owned
QEMU55832; stopped-image extraction is under
`maps-current-20261114-r92/private-readback/r92-private/current-api-r92`.
Its child.log SHA256 is
20cffa8200f9ee579e26019241747b2a90fcd5465b25e85e71365fc93027a047.
No signed ARM pass is claimed for that candidate.

The initial checker had fixture identifier collisions; the first SDK emitter
lacked its output directory. A view helper's fixed JNI argument array escaped
in emitted C and required a bounded stack argument instead. Those failures
remain retained. Native attempts r4 and r5, and host checker r4, hit observed
shared disk-growth limits and are not successful qualifications. A separate
link of retained r5 C passed, but deployment selects the later complete r6
producer pass. The initial checker compiler invocation accidentally retained
the guard's default 2 GiB RSS; subsequent checker builds and final checks used
the required explicit 600 MiB cap.

The final signed ARM suite passed in fresh guest r93. Its retained child log
contains BITMAP-BUFFER-PASS, EGL-SHARED-DISPLAY-PASS and CURRENT-API-PASS;
the runner closed input after readiness/pass and observed child exit 0.
The complete UART frame reconstructed without removals (22515 bytes, 44 chunks).

| ARM evidence | SHA256 |
| --- | --- |
| maps-bitmap-api-uart-20261114-r1/full.log | 892d7c53cdbe6861f02a71472ad8157392a295bd75fdabce0080aeec2bdc433b |
| maps-bitmap-api-readback-20261114-r1/archive.json | a799345f57b5a61fbcd591fb8e6e9c9c8562d3086fc556f949d811986f82eeb0 |
| maps-bitmap-api-child-20261114-r1/child.log | c9e8c409ab87d44b0e269438c4c95c154fda49c57113dd301c7233adf575cad3 |

## Real Maps r93

Source change 7796d94ba was exercised in a fresh single-launch protected Maps
session. Actual Google Maps rendered Paris tiles, a 15-minute/3.6-km Eiffel
Tower-to-Louvre Museum route, blue route geometry and its alternatives.
Preview showed "Head toward Pont d'Iéna"; its next-turn control changed the
instruction to "Turn left onto Pont de la Concorde (signs for Chatelet)" with
the matching mapped junction. Search/route entry and scene updates had visible
delays; sustained responsiveness is not qualified. Place imagery and Google
account entry were not completed in this run. No authentication is claimed.

The private Maps log has no native_copy_to_buffer missing-binding, uncaught
worker/main-loop failure, System.exit or EMFILE marker. It does contain caught
Cronet module/native lookup exceptions; these remain relevant to full support.
The signed ARM transfer regression, rather than this route alone, establishes
the bitmap method's buffer/storage/locking behavior.

Descriptor captures are non-atomic, with matching process start-time brackets:

| Phase | PID | Descriptor entries | Framework APK handles | Unavailable targets |
| --- | ---: | ---: | ---: | ---: |
| GMS ready | 2665 | 180 | 2 | 1 |
| Maps onboarding | 6925 | 179 | 2 | 0 |
| Maps after route | 6925 | 257 | 2 | 1 |

The controller accepted --stop and ended user-stopped-no-authentication-claim,
empty error and two cleanup survivors. Both copy/launch terminals checked
the selected persistent volume (UUID 6a128cc7c7fc4f57b9ff2ec316aed5ea).
Private results and the complete signed API run were copied there and synced;
the successful mount check, copied receipt and shell prompt were observed
before stopping owned QEMU70309. PID absence and no open boot/data image
handles were verified before debugfs read-only extraction. Private log hashes
match both manifests; private and exported receipts compare identical.
Read-only e2fsck passed under the original caps. The 600166-ms storage watch
retained minimum disk 7941083136 bytes and minimum MemFree 4177168 KiB.
r91, r92 and r93 are stopped.

Evidence is under maps-current-20261114-r93/private-readback/r93-private/results,
the sibling descriptor/watch directories, and the following external artifacts.
The Maps UART interval reconstructed without removals: 1429297 bytes/2792 chunks.
The initial incremental snapshot rejected an incorrect prior-receipt hash;
the retry used the measured hash. The first account plan's child passed but
its 64-MiB disk-growth guard failed; the fresh retry passed under that cap.

| Runtime evidence | SHA256 |
| --- | --- |
| maps-bitmap-account-uart-20261114-r2/interval.log | 1edaf02e5386982cc429b196364d88ab46da1088e1d76f578573625b3ce92b16 |
| maps-bitmap-account-readback-20261114-r1/archive.json | 1231a5dfea6b22c1037a3117a4cbe362926c1b5f3245a0b0cdd218980918beed |
| Same account readback/exported-receipt.json | 5106d1546f460660a9441af3ab15e7c418530c5e050f09ce1f3d43f481bbb9ec |
| Private results/broker.log | ffdf402d45784cdc3b02b7d29db1a9e30719b88a82da530b1664681c11620e5f |
| Private results/maps.log | 227ee24c98ae8a28afcbc24b8d6dcb58d108a4c152f40a89de6c5dab5bc304a7 |
| maps-current-20261114-r93/turn-preview.png | ca681aa48c1297d222364003198d4f4424f05723ec16241f37053f3725ee13f9 |
| maps-current-20261114-r93/second-turn.png | 6af912e8489f5112fecff50dfd5276a94fb0eb56c3a670ad5b4d671b4929df67 |
| Same guest/private-readback/descriptor-inventories.sha256 | d962e8e43b243795e051fdd25acf21649ff853216a832eaaf80ca8d4ecd0afa8 |
| Same private readback/storage-watch.log | 52408f0b627c19decbd4f63765327702c50819e23d62525cedadaee350787fdc |
