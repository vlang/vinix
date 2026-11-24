# Native window and personal-data decoder ownership

The native window fix at `12ab92b0d611e7471d70f2dfacd49e6eb9fe751a`
releases the temporary frame and event records after copying their decoded
fields into the result. It appends decoded elements by value and releases
their owned fields directly. The personal-data fix at
`a75fe4c967f1503830e41207b9976c0153042126` uses the same ownership rules for
the inventory and its rows. Each decoder also releases partially decoded
fields on failure.

The baseline broker retained 560,000 bytes across 1,000 iterations. Tracking
parts of one iteration traced all 560 bytes to frame decoding. The generated C
showed five 112-byte temporary structures for the frame and its two controls.
The fixed broker retained zero bytes through fragmented frames, focus, editing,
rendering and retirement. The SDK frame/event regression retained 743,424 bytes
on the baseline and zero after the fix over 256 complete and partial-record
cycles. [SDK regression](../../tools/packages/appsdk/window_ownership_test.v)

The separate personal-data decoder regression retained 143,360 bytes on the
baseline and zero after the fix over 256 complete and partial-response cycles.
The Software page retained zero bytes over 1,000 inventory, rendering and
confirmation cycles with valid, growing and malformed reports. Both codec
regressions passed ASan/UBSan with leak detection disabled. The personal-data
fixture typechecked for AArch64 and x86-64 Linux.
[Personal-data regression](../../tools/packages/pkgprotocol/personal_data_test.v)

The signed protocol-2 Memo workflow passed in both QEMU guests. AArch64
completed in 34.6 seconds and x86-64 in 58.3 seconds. The tests exercised
ordinary-account Unicode input, explicit saving, empty replacements, rollback,
EOF close, policy denial and publisher revocation. The guest controller
enabled the V globals used by the current session manager. The Software broker
and inventory UI allocation tests ran on the host with the retained headless
UI module. [Guest driver](window-check.v)

The full Software functional run passed. The allocation suite proceeded past
native windows, personal data, policy, metadata, catalog view and health,
then stopped at the cleanup view. A direct replay retained 120,000 bytes
across 1,000 cleanup iterations on both the baseline and the fixed source.
The SHA-256 of the checked suite archive is
`cc294a5fa64ffb7712d610ec15c25208f44a030cacf7472e1ee9a39c4e5bf78f`.
[Software suite evidence](/Users/alex/.local/state/vinix/r14-window-allocation-QnOp6w/software-suite-final.tar.gz)

The independent qualification archive checker verified 148 sealed entries,
including both guest runs, decoder and broker binaries, source revisions and
measurement logs. The archive SHA-256 is
`6237c256d7d217d497d521b6615d9d3a234c40db1f0315e117d5ac7ab623f95a`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-window-allocation-QnOp6w/qualification.tar.gz)
