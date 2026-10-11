# Process dumpability

PR_SET_DUMPABLE now stores 0 or 1 and PR_GET_DUMPABLE returns that state.
Fork inherits it. An ordinary exec resets it to 1; mixed real/effective user
or group credentials select 0. Effective user/group changes also select 0.
A nondumpable process's maps, smaps and auxv are protected from other processes
with matching credentials; the process itself and CAP_SYS_PTRACE retain access.

Build the desired kernel, then run `tests/dumpability/run` or
`tests/dumpability/run --arch amd64`. The runner accepts the same
isolated-worktree environment variables as tests/network-options. The guest
checks retained values, invalid inputs, fork/exec, credential resets and actual
procfs reads from a same-UID peer.

Mixed real/effective user or group credentials also emit `AT_SECURE=1` in
the initial auxiliary vector, with matching UID/EUID/GID/EGID entries. Ordinary
matching credentials emit zero. The guest checks these after real execs on both
architectures. This closes the existing-credential secure-loader part of SEC4;
executable set-ID and file-capability transitions remain separate work.

The independent guest is maintained in `dumpfixture/core.v`, using native libc
declarations from its ABI header. Both real exec child modes and all 14 original
check sites are retained, producing 15 verdicts across the UID/GID cases. The
runner compiles the selected V target and preserves its 300-second budget.

This addresses the dumpability portion of OB2. ELF core writing, RLIMIT_CORE
output limits, privileged dump destinations and file-capability/set-ID exec
integration remain to be implemented; this change does not create core files.

The [native V controller](../native-guest-tools/abi-guests.md) accepts
`--state-dir FRESH-DIR` to retain artifacts and `--build-only` to qualify the
fixture separately. Every run snapshots an already-built matching kernel.
