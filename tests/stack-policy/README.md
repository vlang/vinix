# Opt-in syscall stack policy

`MAP_STACK` (0x20000) now tags private anonymous mappings and rejects shared,
file-backed, or executable stack requests. PROT_NONE reservations may be tagged;
only their currently readable+writable, non-executable portions authorize a
syscall stack pointer. The initial main stack is tagged automatically. Existing
split/fork/remap paths retain the mapping flags.

`prctl(0x56490001, action, 0, 0, 0)` provides a Vinix loader/runtime contract:

- 0: query mode (0 disabled, 1 audit, 2 enforce).
- 1: enable audit; invalid entries increment a counter and calls still run.
- 2: enable enforcement from a valid tagged stack. Invalid entries terminate
  the process with SIGSEGV, including if it installed a handler.
- 3: query the invalid-entry counter.

Mode can only strengthen until exec installs a new image. Fork inherits the
mode with a fresh counter; exec clears both. A runtime opting into enforcement
must tag every thread stack and alternate signal stack before using it. Policy
is disabled by default to retain ordinary Linux syscall behavior.

Run `python3 tests/stack-policy/run.py` or add `--arch=amd64`, with the same
worktree/sysroot environment overrides as the dumpability runner. Guests issue
actual syscalls on tagged and untagged alternate stacks, exercise split/fork,
protection changes and exec, and check audit counts and enforced signal status.

This supplies the opt-in tagging/checking portion of SEC6. It does not enable
these rules for existing Linux binaries without cooperation from their runtimes,
add syscall-instruction pinning, or guard kernel stacks. The check inspects VMA
metadata under the pagemap lock and allocates no memory or faults pages in.
