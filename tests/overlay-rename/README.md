# Overlay rename qualification

This V controller runs native Vinix guests with a private tmpfs overlay and,
for disk cases, a fresh 128-MiB ext2 volume. Root prepares the mounts and transfers
the private directories; all rename workloads run as UID/GID 1000 after clearing
supplementary groups. An unprivileged mount attempt must fail with `EPERM`.
The parent performs the final unmount/remount check after the worker exits.

Build each kernel in an isolated worktree with the dependency symlinks described
in `AGENTS.md`, then use fresh result directories:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=1 build-support/run-v-tool.sh \
  tests/overlay-rename/run.v --arch x86_64 \
  --kernel-dir /path/to/x86-worktree/kernel --state-dir /path/to/fresh-x86-result

V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=0 build-support/run-v-tool.sh \
  tests/overlay-rename/run.v --arch aarch64 \
  --kernel-dir /path/to/arm-worktree/kernel --state-dir /path/to/fresh-arm-result
```

The ARM command uses HVF on macOS; use TCG without host acceleration. The
controller uses the maintained guest build/boot tools, a declaration-only musl
ABI header and `mke2fs` (`VINIX_MKE2FS` can select it). It owns a QEMU process with
networking disabled and records kernel, fixture, ABI, init, ISO and disk hashes
in `receipt.json`. Guest serial output is retained in `serial.log`. A positive
verdict is required for every selected case; assertion failures fail the run.

The default `--case all` includes:

- `atomic`: two phases of 1,000 tmpfs-upper replacements, with concurrent opens
  and directory listings. The second phase adds nine filler names to exercise
  map growth and collision shifts. Reads must return one complete eight-byte
  version, and the destination must stay present. Each phase holds the original
  descriptor for 6.5 seconds and checks content, UID 1000, mode 0600 and nlink 0.
  It prints slab samples before and after the phases.
- `failure`: a lower tmpfs file has a 256-byte basename that ext2 cannot encode.
  Renaming an upper file over it must return `ENAMETOOLONG` while preserving both
  merged paths and the lower content. This reaches the real backing rename;
  it uses no fault injection or extra authorization.
- `disk`: an ext2 upper file replaces an existing upper inode held past the
  grace period. A lower source is copied up and renamed, leaving its old merged
  path hidden and its lower content unchanged. An upper source replaces a
  whiteout destination. Empty upper directories replace one another in the
  same parent and across parents, verifying both parent link counts. After
  unmount/remount, regular upper content, ownership, permissions and source
  removal must persist.

Results from 2026-10-13 are retained under `build/development17-20261013`:

| Run | Result |
| --- | --- |
| `overlay-x86-before-e` | Saved pre-fix kernel: 57 missing opens and two missing listings in the first 1,000 replacements. |
| `overlay-x86-failure-before-d` | Saved pre-fix kernel: errno 36, source preserved, merged destination lost. |
| `overlay-arm-failure-before-a` | Same failed-backend destination loss on the saved ARM kernel. |
| `overlay-x86-after-a` | All cases pass; 2,368/2,112 concurrent reads, zero missing paths, listings or bad data. |
| `overlay-arm-after-b` | All cases pass; 3,968/2,944 concurrent reads, zero missing paths, listings or bad data. |
| `overlay-x86-after-b` | Final fixture also checks cross-parent directories; all cases pass, 2,208/2,816 reads, zero errors. |
| `overlay-arm-after-c` | Final fixture also checks cross-parent directories; all cases pass, 2,176/4,096 reads, zero errors. |

The final kernels were built from isolated `9b01dbca2` worktrees plus the six
filesystem changes committed in `eefa7da3a` and this overlay/ext2 patch. Kernel
link shuffling used seed 17. The preserved V compiler snapshot
`/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/v-from-bootstrap`
was used after the live compiler began rejecting baseline pointer syntax; the
compatibility retry also rejected the required `-target-libc-headers` flag.
The initial ARM attempt ran out of disk space, then its fresh build passed.
Those failed build and fixture-compilation logs remain separate from guest passes.

| Input | SHA-256 |
| --- | --- |
| Before x86 kernel | `abbf8e176bd68c45191c3c6274052e1bca262ed7b95a20b4d05449134dec10f1` |
| Before ARM kernel | `2033980d61274fd37a0b69ad3df04aca261162de0a40a8c5d9f37ffeb6573c2d` |
| Final x86 kernel | `4ff3454595830483103c70d29328834a9743f4312ec2561c2faa8472c0ac163d` |
| Final ARM kernel | `fe2746f27759c3f1e27166fa0c785a093e73987a21e7d01a50766310c063bd26` |
| Final fixture | `ce25cf4add6d7056388b1d847a3a16eccfb21912a009762efcc9730dc74b7cea` |

An independent lifetime review checked the generated C, cloned-name ownership,
held descriptors, lock ordering and post-commit retirement. It found the missing
cached parent link-count update; the final patch and directory assertion address
that finding. The final review is retained in `overlay-lifetime-review.md`.

Both final kernels also passed the native authenticated HTTP/account/job/build
gate (`overlay-arm-http-a` and `overlay-x86-http-a`), with 19 independently
validated records each. The allocation allowlist audit still fails; its 182
file/kind counts match the pre-fix audit exactly. The allowlist was not expanded.

The final ARM kernel passed the full `ops,churn,cache,idle,apps,drag` desktop
harness run. All 36 syscall batches of 200 operations retained zero bytes per
operation, and all four 300-process churn batches retained zero bytes per run.
The cache workload wrote 32 MiB and recorded 16 MiB cached. Idle, application
launch and drag met their process-count and duration checks. The report and
screenshots are retained in `overlay-desktop-perf-a.json` and
`overlay-desktop-shots-a`; `overlay-perf-evidence.log` records the report checks.

This qualification does not close overlay memory retention. After the two
phases and grace periods, both final kernels retain 4,023 additional size-256
objects, 2,012 size-96 objects and 4,044 size-16 objects. The pre-fix ARM control
retains the same size-256/size-96 counts and 4,045 size-16 objects. An earlier
4,000-replacement phase exhausted the existing owner metadata budget; its x86
log records `Denied.owner 1`, `Requested 8198`, `OwnerBytes 61898188` and
`OwnerLimit 61902848`. The bounded fixture exposes this growth rather than
claiming a leak-free overlay. `overlay-evidence.log` records the comparisons.

Durable whiteouts across overlay remount, retained-directory/CWD stress, crash
consistency, unsupported rename flags, full OCI security/delegation and mainstream
rootless-runtime acceptance remain open. The disk persistence test qualifies
regular upper files; it does not qualify persisted whiteout hiding.
