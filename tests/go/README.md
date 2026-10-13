# Go smoke test

The maintained V [reference SDK stager](../../tools/development/stage-go.v)
and [development guest controller](../development/README.md) provide a separate
pinned ordinary-account compile/run gate without invoking the overlay builder:

```
V_C_ERROR_BUG_REPORT_DISABLED=1 v -cc cc run tools/development/stage-go.v \
  aarch64 /path/to/prepared-go-overlay /path/to/new-go-stage

V_C_ERROR_BUG_REPORT_DISABLED=1 \
VINIX_DEVELOPMENT_REFERENCE_SDK=/path/to/new-go-stage/sdk \
VINIX_DEVELOPMENT_REFERENCE_PROFILES=go \
tests/development/run-guest aarch64 /path/to/kernel /path/to/staged-tools /path/to/new-state
```

The gate builds and executes the goroutine/channel/file project in two fresh
UID/GID 1000 workspaces and independently checks SDK/runtime/tool pins and
matching program/data artifacts. Go uses its local toolchain, private cache,
offline resolution, trimmed paths and no VCS stamping. This gate covers the
pure-Go reference project; cgo, network and broader module workflows retain
their own acceptance checks.

`smoke.go` is compiled and executed inside the AArch64 Vinix userland. It
checks the Go runtime, filesystem access, goroutines, channels, synchronization,
timers, subprocesses, cryptography and TCP loopback networking. When the native
GCC toolchain is present, it also compiles and runs a cgo program.

Build the Go overlay and userland with:

```sh
./scripts/build-go-aarch64.sh
./scripts/build-userland-aarch64.sh
```

The VM userland boot suite invokes `smoke.sh`, which checks `go`, `gofmt`, and
`go env`, builds a pure-Go program and runs the resulting native executable
automatically. Its cgo check uses the GCC installed by the aarch64 userland
builder.
