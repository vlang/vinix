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

Real Maps validation for the final candidate is pending.
