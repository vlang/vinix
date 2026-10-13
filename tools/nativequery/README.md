`Controller.call` exchanges newline-delimited JSON with a native executable and
serves synchronous V callbacks. `Value` retains raw numeric tokens, including
unsigned device/inode identities and arbitrary-width results. Callback failures
remain owned native error objects; a returned binding index rethrows that same
object rather than rebuilding it from text.

Private pipes are moved above descriptors 0–2 before spawning. SDK spawn actions
duplicate only the child's stdin/stdout, preserving the caller's open, closed
and close-on-exec standard slots. Writes are nonblocking, reads poll in short
steps, and both observe the native command guard. Retirement closes stdin,
allows five seconds for exit, then retires the reserved private process group,
closes stdout and performs the sole reap. Concurrent and nested calls own
separate pipes, children and saved errors.

The optional `started` callback observes the reserved PID while the call owns
it. It must not wait for or reap the process. The caller owns its callback
context until `call` returns.

`tests/native-host/stdio-test` compiles its native query automatically and checks
the real callback descriptor matrix, saved error identity, EOF, repetitions,
concurrent calls and signals. It invokes no Python adapter.
