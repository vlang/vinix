# Metadata-only UART boundary inspection

`uart-boundary-metadata.v --maps-account IMMUTABLE_UART SHA256 FRESH_OUTPUT` reports
bounded control/empty-field offsets without exposing payload or chatter.
It requires a pinned mode-0400 single-link regular file of at most8MiB,
rechecks input bytes and writes exclusive read-only metadata outside Git.
`--self-test` covers controls, exact offsets, duplicate/embedded prefixes,
leading/repeated/trailing spaces, malformed bounds/order and final-LF checks.

`metadata_ready` requires complete ordered headers. Distinct `bounds_ready`
permits only an empty-removal plan bound to unique canonical BEGIN/END and the
original raw hash. The unchanged historical reconstructor still decides
completeness. No collector change, byte repair or normalization was added.
The historical `uart-frame-audit.v` and its original logic remain separate.

Independent review and guarded compile/selftest/actual audit passed. Final
compile:1.302s/340,000,768bytes sampled RSS; selftest:0.238s; actual audit:
0.214s/11,878,400bytes. Limits remain600MiB RSS/300s/1GiB reserve, with512MiB
observed growth for compile and64MiB for read checks. Complete cleanup and zero
swaps were recorded. The initial V3 json2 Signal/os.Signal compile collision
is preserved; the local record was renamed FrameAnomaly.

Evidence is under `/Users/alex/.local/state/vinix/android/maps-binder-identity-runtime-audit-2026-10-29-r1`,
in maps-diagnostic-classifier-build-r1 and maps-diagnostic-classification-r1/r2.
Frozen source SHA: `914613d3d18e4be13101653ac7eb14aeb6c9168e01d5ae4f04d1cf3352cc745e`;
executable: `8bcd22a6ed294bd5e7e90e15c64590f1c6f39701b4c796b4262320fe88807fd0`.
The owner seals the full runtime bundle separately.

For interval `99a81170ae2d902d9760e2af2c00aebcf1f602437d13cde79f094e72648a00a5`,
CR13 at788124 splits CHUNK993 after its header space. CHUNK995's complete
selected header is absent; at789768 the next recognized index is996.
Recognized2815frames/2813chunks disagree with declared2814chunks. Strict
collection and unchanged zero-removal reconstruction both reject this Maps
export. No valid imported Maps receipt exists; GUI captures remain manual
evidence. The separate authenticator/TLS-v3 fixture checks remain qualified.
