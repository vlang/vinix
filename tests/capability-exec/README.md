# Capabilities across exec

The kernel honors `no_new_privs` when recomputing capabilities for an
executable. Its permitted set cannot exceed the permitted set before exec,
even when a root process retains a larger bounding or inheritable set.
Effective capabilities remain a subset of the resulting permitted set.
Activating an already permitted capability is allowed, as it is through
`capset`. Ordinary exec without `no_new_privs` retains existing behavior.
This follows the [Linux no-new-privileges contract](https://docs.kernel.org/userspace-api/no_new_privs.html)
and the permitted-set intersection in [Linux commoncap](https://github.com/torvalds/linux/blob/master/security/commoncap.c).

The ambient capability commands use their Linux ABI numbers: IS_SET=1,
RAISE=2, LOWER=3, CLEAR_ALL=4. IS_SET observes without changing the set.
Dropping permitted or inheritable bits through `capset` also clears those
ambient bits, maintaining `ambient ⊆ permitted ∩ inheritable`. Otherwise an
ordinary nonroot exec can regain a capability that the program dropped.

`guest.c` tests actual kernel syscalls and repeated exec of the same image:

- Root drops every permitted capability while keeping bounding and
  inheritable candidates. With `no_new_privs`, two execs cannot regain them.
- A restricted permitted set keeps bits in both halves of the capability
  ABI; effective bits may activate only within that prior permitted set.
- Mixed real/effective credentials retain secure-loader and dump protection.
- The flag survives fork and exec and cannot be cleared.
- Ambient query, raise and lower commands behave correctly. Dropping either
  prerequisite set clears ambient bits and prevents their reintroduction.
- A valid nonroot ambient capability survives exec with `no_new_privs`, while
  KEEP_CAPS resets.

Build both tracked kernels in an isolated worktree, then run:

```sh
export VINIX_VM_RUNNER_ROOT=/path/to/main-checkout
export VINIX_KERNEL_DIR=/path/to/worktree/kernel
export VINIX_AARCH64_SYSROOT=/path/to/main-checkout/build-aarch64-userland/sysroot
export VINIX_QEMU_RT_NO_BUILD=1 VINIX_QEMU_AUDIO=off
python3 tests/capability-exec/run.py
VINIX_AMD64_KERNEL=/path/to/worktree/build-amd64-kernel/bin/vinix \
  python3 tests/capability-exec/run.py --arch=amd64
```

The guest is compiled with warnings treated as errors. The runner requires
every test marker and the final verdict, and uses disposable VM assets.
On 2026-10-02, both tracked builds and all six guest sections passed on each
architecture. The generated C of both builds contains the scalar exec ceiling
and ambient-drop mask, without any added allocation in the exec helper.
The saved pre-fix ARM kernel at `78c2676f` passes the ordinary root control
but fails the first root `no_new_privs` capability-regain assertion.
The exec helper's generated C uses only scalar capability records; this fix
adds no allocation, pointer ownership or retirement rule. Its security
transitions and test cases received an independent review.

Local evidence: `/tmp/vinix-capability-exec-{arm,amd64}-guest.log`,
`/tmp/vinix-capability-exec-arm-baseline.log`, and
`/tmp/vinix-capability-exec-{arm,amd64}-build.log`.
This closes the capability-ceiling bug. SEC4 still needs executable set-ID
and file-capability transitions, nosuid integration and descriptor hygiene.
