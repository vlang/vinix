# Mandatory filesystem and process domains

The guest regression runs as initial-namespace root. It installs labels and a
bounded permission matrix, seals both, then activates a domain through exec.
It verifies that capabilities cannot bypass the policy on retained and
SCM_RIGHTS descriptors, aliases, bind mounts, overlay copy-up, metadata,
transfers (including a separate denied-pipe domain for tee/vmsplice), shared mapping protection increases, exec/interpreters, privileged
audit snapshots, inotify instances and cross-domain process control. Own-domain
operations continue to work. Policy setup in another user namespace is denied.

Concurrent close of the last memfd descriptor during exec exercises the loader
reference lifetime. Repeated allowed and denied operations report their live
slab retention. The FIFO check isolates the interface-box allocation class;
the pre-existing unretired FIFO node is outside that check.

Build each kernel in its own worktree with the dependency symlinks described in
AGENTS.md, and prepare the musl sysroot/cross compiler as for the other kernel
guest tests. Then run from this repository:

```sh
tests/security-mac/host-run.sh
VINIX_KERNEL_DIR=/path/to/arm-worktree/kernel tests/security-mac/run.sh aarch64
VINIX_KERNEL_DIR=/path/to/x86-worktree/kernel tests/security-mac/run.sh x86_64
```

`CC` selects clang for the ARM test; `VINIX_AARCH64_SYSROOT` selects its sysroot.
`CC_AMD64` selects `x86_64-linux-musl-gcc` for x86. `VINIX_QEMU_TIMEOUT` overrides
the 300-second guest deadline. `VINIX_MAC_STATE_DIR` fixes the artifact directory;
the shared kernel-gaps harness prints its location and retains the serial log.
The runner disables guest networking to reduce unrelated allocation noise.
Scheduling checks use direct syscalls because musl stubs several libc wrappers.

These tests establish the listed enforcement boundaries. The policy is an
initial bounded implementation, not a complete general LSM, network/IPC policy,
information-flow policy or evidence of Linux security parity. Deployment
instructions and the ABI are in [the utility documentation](../../tools/security-mac/README.md).
