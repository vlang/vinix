Build `run.v` with V into an external executable, then run it. Set
`DRM_FENCE_TEST_BINARY` to retain the ASan/UBSan executable outside Git.

The fixture copies the complete production syncobj module and injects locks,
atomics, scheduling and time. Eight hundred success/error completions check
first-result preservation, queued and late callbacks and repeated signals.
Deterministic scheduling before the exact fence lock tests competing producers.
Callbacks keep the existing under-lock contract. Fixture-only metadata cleanup
runs after every synchronous caller and callback returns; native metadata
retention is unchanged. This is not a kernel heap or hardware concurrency test.
