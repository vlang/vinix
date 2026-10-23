Native input now drains at most 64 queued records before the next rendered frame. Each record gets a checked JNI local frame and a separate decoder call so text buffers and Java local references are released before processing the next record. Pending exceptions, shutdown, malformed records, and EOF stop the batch.

The same host fixture extracts the baseline and fixed production functions and the actual pipe protocol structures. The baseline consumes only DOWN and fails the ordered mixed-event assertion. The fixed source passes 11 scenarios in normal and AddressSanitizer builds: mixed input ordering, the 64-record limit and continuation, text stack reuse and local-frame bounds, empty/4096-byte text, pending exceptions, failed frame pushes before and during a batch, stopped runtime, empty pipe/EOF, malformed headers/lengths/partial payload, and disabled input.

Run the current implementation from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/native-android-ws/input-batch-host.v
/Users/alex/code/v/v_old -nocache -cc cc run tests/native-android-ws/input-batch-host.v asan=true
```

Validate retained hashes or replay both frozen source versions:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/input-drain/validate.v
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/input-drain/replay.v
```

The fixture uses real OS pipes and stubs Java dispatch/JNI local frames. ASAN checks host memory safety; frame/reference assertions verify the wrapper contract through those stubs. Leak detection is disabled for unmanaged V harness allocations. Full Maps timing and interaction evidence belongs to the adjacent `maps-input-latency` receipt.
