# Fixed overflow identity policy validation

The candidate adds only two `add_procfs_text` entries in `kernel/fs/procfs.v`:
`overflowuid` and `overflowgid`, each containing `65534\n`. Their initial mode is
`0444`; the existing procfs text backend rejects writes and truncation. User and
network namespace guards are unchanged. This is a prerequisite for Bubblewrap,
not evidence of a working browser sandbox or Google account login.

Kernel source base: `577a2d8c29ba6d4a95a655d507ef38414d3b8c77` plus retained
`source.patch`, SHA-256
`432db2c04daf81f5ac41c4feb29bcf78c73b2ad4c0c34fdd1cccf5ed86267f62`.

Complete external state root:
`/Users/alex/.local/state/vinix/android/procfs-overflow-2026-10-26-r1`.
Generated C, binaries, build-input inventories and logs remain there.
The complete typed file/mode/symlink inventory is retained outside that bundle at
`/Users/alex/.local/state/vinix/android/procfs-overflow-2026-10-26-r1-inventory.json`,
SHA-256 `00333564fade4b47ae6e40e7db1bce48f9ce41f18bca2765a2bcfc5d86383077`.
The retained `inventory-host --check BUNDLE EXTERNAL-MANIFEST` re-read passed.

Both isolated worktree builds passed. Their retained manifests are:

| Architecture | Bundle | `sha256.json` SHA-256 | Kernel SHA-256 |
| --- | --- | --- | --- |
| AArch64 | `kernel-aarch64` | `36654a8d798f3c44d152c410014666023c3a9dc606e1eb6766bc1cca41b3fc68` | `ee6aa1acb31f11b8abf16c4001149ccb92e8f8fe35d0106342bbdbad6e7e57fd` |
| x86-64 | `kernel-x86_64` | `7021e6e7faae589b2ea257d4c084e9a79489e767a9939596e21802f180e6103a` | `ce9eae8284828885cde2a8c484c0c5dbf4f1ae0e600d07aa3052955830053378` |

Both used the frozen V compiler SHA-256
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.
The kernel builder retained the compiler/library source closure, dependencies,
applied diff, generated C, commands and before/after input checks. Its optional
patch mode passed self-tests for application, inapplicable patches, changes
outside `kernel/` and untracked output rejection. Existing inventory mutation
and tracked-file/symlink tests also passed (`builder-selftest-r2.log`).

The fixture compiled and linked as static ELF64 for each architecture:

| Architecture | Preparation | Executable SHA-256 |
| --- | --- | --- |
| AArch64 | `prepare-aarch64-r4` | `1e657adfa63b412226ec746fe078235b26a3b2cd65432e5efdcb9c8716850fbf` |
| x86-64 | `prepare-x86_64` | `017eaac083243dd80dbd2b73f465fc575c60038ac2cd88328db2b9e2ad3d1115` |

Fixture source SHA-256:
`7ec2f5fc4cb4ed263fa31be125b839c86b296214643d8822a2073aa3999be1f4`.
Preparation records the GCC driver hash, serial-helper source inventory and
link command; it does not retain a complete cross-compiler/libc closure. Initial
attempts exposed an absent default Clang sysroot and a fixture module-name
mismatch; the successful preparations use direct musl GCC and the corrected
module declaration.

Guest runtime checks use the same prepared AArch64 executable against the old
and candidate kernels:

| Run directory | Result |
| --- | --- |
| `run-baseline-aarch64` | Expected exit 1: `PROCFS OVERFLOW FAIL: open value errno=2` |
| `run-aarch64` | Exit 0, all three root/application/final PASS markers |
| `run-x86_64` | Exit 0, all three root/application/final PASS markers |

The old kernel is the frozen AArch64 r3 build, source revision
`ee0d3b6ff3d2586a0e5f35a27042643afaa298f3`, kernel SHA-256
`ac90558eac4f2ea6b74c72c3f519370e98e9f88b0a5384aa82cc386bdd1876ce`.
Each run retains its own kernel, init, preparation, serial log and hash receipt.

An independent ownership review found no new lifetime: both values compile to
the same static literal, procfs text reads do not allocate replacement text, and
the frozen V `string.free` skips literal strings. The fixture also checks
retained writable descriptors after dropping privileges, repeated reads and
failed namespace requests without changes to namespace identities.
