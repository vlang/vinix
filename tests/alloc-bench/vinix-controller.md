# Native Vinix allocation runner

`run-vinix` invokes `allocationhost` directly in V. It prepares and verifies
the rootfs, ISO, kernel and libc inputs, records the launch configuration and
supervises its private VM through complete serial verdicts. Compiler and VM
process groups stay owned until descendant retirement and the sole reap.

See [native allocation qualification](../native-allocation-tools/README.md)
for host profiles, independent fixtures, signal and log checks. The earlier
Package Session bridge and Python entrypoint are retired; their original
Git provenance remains in the translation receipt.
