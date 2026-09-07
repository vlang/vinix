# Go smoke test

`smoke.go` is compiled and executed inside the AArch64 Vinix userland. It
checks the Go runtime, filesystem access, goroutines, channels, synchronization,
timers, subprocesses, cryptography and TCP loopback networking. When the native
GCC toolchain is present, it also compiles and runs a cgo program.

Build the Go overlay and userland with:

```sh
./build-go-aarch64.sh
./build-userland-aarch64.sh
```

The VM userland boot suite invokes `smoke.sh`, which checks `go`, `gofmt`, and
`go env`, builds a pure-Go program and runs the resulting native executable
automatically. Its cgo check uses the GCC installed by the aarch64 userland
builder.
