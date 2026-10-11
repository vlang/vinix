# Native desktop performance fixtures

`test-runner.v` runs `runnerfixture` directly. Its independent transcript cases
preserve the maintained verdict, local dictionary and cleanup assertions.
Production plan, preparation, console, QMP and saved-driver paths run against
private native guest children and Unix sockets. No CPython adapter is loaded.

`perfconsole/abi.h` names the system `siginfo_t` and PTY declarations; supervision,
serial draining, status inspection and process retirement are V implementations.
Fixtures check SDK status on both host architectures, serial backpressure and
cleanup before descriptor reuse. See [qualification](native-tools.md).
