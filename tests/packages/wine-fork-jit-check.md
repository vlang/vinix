# ARM translated-fork failed diagnostics

The additional AArch64 attempts remain **failed or incomplete diagnostics**.
They do not qualify the 32-fork arithmetic workload, Wine, or translated
application distribution. The existing
[translated-fork regression](wine-translation-fork-check.md) and its complete
original evidence remain required.

| Retained attempt | Observed result |
| --- | --- |
| `tools/altstack-c6b5455e` | Preparation refused the long QMP Unix socket pathname; no guest result. |
| `raw/altstack` | Failed after 10.304 seconds: ordinary UID/GID 1000, zero supplementary groups and no W+X exception reached the probe start, then the translated processes emitted internal QEMU SIGSEGV diagnostics after the first fork. |
| `raw/jit01` | Incomplete capture: QEMU could not reopen `/dev/console` for its log under the ordinary account. The guest's capture-only PASS did not supply the required probe-start marker; no final result or input-verification map exists. |
| `raw/jit02` | Failed after 73.415 seconds with the guest's timeout marker while collecting generated-code output through inherited stderr. No completed arithmetic/fork result. |

The maintained [controller](wine-fork-jit-check.v) and
[guest](wine-fork-jit-guest/main.v) capture JIT diagnostics without changing
the original arithmetic probe or its expected results. Capture completion
alone does not judge that workload. This checkpoint introduces no production
translator or kernel fix and makes no claim about the cause of the failure.

The complete external archive is:

`/Users/alex/Library/Caches/vinix-codex/section14/wine-arm-fork-diagnostic-20261026.tar.gz`

- Archive SHA256: `6f724e8c7e838a9b8534ad11a8c08e9c8cec4dffe6e47899168f481ef1ff9f35`
- Embedded `bundle.sha256`: `48a021acf1625ec59528890c1fbea513be8acb7884f16b3295ed329677bbce14`
- Embedded `SHA256SUMS`: `3032a6c088527a4d34d7e454fbf6564f3d5385ad561fe459afd363334d164aa2`
- `capture.json`: `0f45b14fd23e34a54001b2fa982dec7de46dc96e9f6795d315b6dde1d286e087`

The adjacent directory is the sealed archive view. Its `raw` tree retains
`/Users/alex/.cache/vinix-arm-fork-20261026`; `tools` retains
`/Users/alex/Library/Caches/vinix-codex/section14/wine-arm-translated-fork-20261026`.
Both original roots remain in place. The [V sealer](wine-fork-jit-retain.v)
streamed ordinary files with no-follow descriptor checks, hardlinked them into
the new view, recreated literal symlinks, and recorded every object type in
`raw-objects.json` and `tools-objects.json`. The single stale
`raw/jit01/boot/qmp.sock` is recorded as a socket with its mode and size; no
socket content is claimed and the socket itself is omitted from the archive.
Complete raw/view inventories and source, sealer, tar and receipt bytes were
checked again after archiving. The original roots' file bytes were not changed.

Independent verification passed the maintained production streaming archive
checker: gzip CRC/trailer validation and all 121 sealed regular-file payloads
matched the embedded manifest. A separate V verifier compared both originals
and the view against all 150 typed records, checked all 120 `SHA256SUMS` files,
the seven source copies and receipt, sealer and tar pins. Its adjacent
`wine-arm-fork-diagnostic-20261026-independent-review.json` has SHA256
`114a0d430ef15a4332bab1b60689b892b7bb07eee2f342af68fca31c714ac471`.
These checks establish preservation of these failed diagnostics.

Capture used source base `e514fcc3cd3a2fe59f483d63f838ef5abc2abe64` with the new
controller, guest and sealer bytes retained under `sources`. Their respective
SHA256 values are:

- Controller: `3be8410e7cdd55519b58819e7540d1f7db7079b0e02ba8b1ca58ad72e7b66b58`
- Guest: `9aa50265327b14efb5df50fa5c9dc6e18cb83353941203d86aa832cca37c38a4`
- Sealer: `af74f4e976d454000ecd2f8c8245abd1cefdd5c001b2355f0bad788bd2264a98`

The altstack attempt's 9,603 selected-input tuples and JIT02's 54 tuples match
their final maps. JIT01 has 54 initial tuples and no final map. These comparisons
do not re-admit the external inputs or establish reproducibility or a hermetic
build. The complete baseline
`/Users/alex/code/vinix/build/package-wine-translation-fork-qualified-1` remains
an external required input; its historical checker requirements are unchanged.
Current maintained sources do not reconstruct JIT01's earlier fixture bytes;
its generated C, binaries, logs and original input hashes are retained.

The supplied kernel receipt
`/Users/alex/.cache/vinix-linux-compat/altstackclone-20261026/states/kernel-first-arm-prod/receipt.json`
is retained with SHA256
`724884d18e429c89ba4f2ac3e25f8128109dc2db0c43c2e0db9d9240337a3500`.
It was pinned as opaque bytes, not decoded or used to qualify the recorded
kernel build. The literal run argument vectors identify the selected kernel.

Production and ASan/UBSan production sealer self-tests passed streaming and
exclusive copy, empty and large files, nested FIFO inventory, dangling symlink
handling, no-follow refusals and changed-view refusal (`detect_leaks=0`; no
retained-allocation claim). No new guest, image or target build was run for
retention.
