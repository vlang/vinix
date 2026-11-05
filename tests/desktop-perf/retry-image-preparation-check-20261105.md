# Atomic retry image preparation, 2026-11-05

One fresh x86 atomic retry image prepared successfully. No guest was launched;
runtime, memory-flatness and current-main kernel qualification remain pending.
The maintained runtime source worktree remains unchanged at
`984fdc1897c7da4b166e2d93baa548cbe8c48e2d`.

Artifacts are retained at
`/Users/alex/Library/Caches/vinix-codex/section14/perf-six-x86-retry-20261105-01`
(R2). The qualified owner, adapter and compiler are unchanged from
[the adapter qualification](full-observer-adapter-check.md). All W/S, frozen
old runtime R and new R2 failures remain charged together under 4.5 GiB.
The old failure evidence and observation-host state were left untouched.

Fresh before-stage measurements were 2,444,245 KiB apparent and
1,821,552 KiB allocated across all four roots, below the reviewed
2,457,600 KiB existing-state allowance. Tool/profile pins matched; the explicit
SDK remains MacOSX26.5. Fresh complete base capture matched
`fcb2e4351b11b733da9b6a1e5fb182097968773a7af71d3ae3274d77c949ea52`.
Complete old-R captures before and after preparation matched its frozen
`03ce6150f13b2f25454f5fc163d82b1ad8483006372b7261cc0a9a4cfd92ff93` inventory.

The four-root original atomic pre/post preparation audits both returned actual
status 0 with exact markers, unchanged original source/manifest pins, equal
before/after input maps, original group absence and ECHILD. Preparation also
returned actual status 0 with equal complete before/after maps. Its native
child/cleanup receipt has 42 samples, maximum start gap 1.030255500 seconds,
complete window 0.434075416 seconds and ECHILD.

The actual prepared observer ELF is byte-identical to qualified B4 and both
prior images. Generated observer/init C and init ELF are byte-identical to the
previous reviewed atomic preparation. B4 generated C differs only in three
anonymous-type source-path spellings; combined C changes only the literal
legacy include root. Retained strict Clang23/lld23 commands use the explicit
musl/GCC closure, disabled default headers/libraries/config and pointer/format
errors, with no warning suppressions or generated-C edits. Observer/init ELF
logs match prior reviewed static AMD64/NX logs, with no INTERP/dynamic section;
all installed executables have mode 0755. The legacy C hash is unchanged.
These comparisons and the concrete run profile are submitted for independent
guest review; a separate VM cue is required.

| R2 artifact | SHA256 |
| --- | --- |
| prepare-atomic-admitted-01.json | `67543764f789934ee3ad3327d72ab71e206f7df26a71184dc83ed83c51abcf0b` |
| prepared-atomic-01/prepared.json | `3ff9312276e36f00a9802457b1c2eea99eeb51375ea42e6a0adee28c12488fc4` |
| prepare-owner-atomic-01/inputs-before.json and inputs-after.json | `803439131981d95fb028eec98725ab942a70dd5f3e4fc322fc1fde6cffd863b8` |
| audit-atomic-before-prepare-01/audit.json | `533d5fca0129c199ff0d8265139a7fb1acb504674976ce24b4661a64933d22c8` |
| audit-atomic-after-prepare-01/audit.json | `b5b030a413505d6ae4e524c06c40feb11ad41280184e0d0a9e34ab4f77ae5710` |
| handoff-01/status.json | `0e907503ff00bd251b2b4a4062dc42ef253212a9dee027e8ed2d002135470f9f` |
| handoff-01/resources.json | `68d94dc51868e13f1f0fd3494e4dc7d1a4ce562bc8f8e65c6d70bbd024cb9511` |
| run-atomic-01.json | `dddf11423c01efa170b5d775305b6c457fd9728353c1a9541c2e2c2933394a45` |
| prepared-atomic-01/rootfs/opt/vinix-perf/measure | `e7874d55c93a6bb1dd2e0821974885437778535a696ce8f14c9eb7e2df95d21f` |
| prepared-atomic-01/guest/init and rootfs/sbin/init | `a9cf1d430c195f0d475920b3353a1107cbb50e90bf95dadb202d2de22b2bcf6a` |

The prepared tree measured 1,162,103 KiB apparent, below the 1,441,792 KiB
forecast by 279,689 KiB. Post-stage totals were 3,614,906 KiB apparent and
2,669,832 KiB allocated, with 25,010,452 KiB free. Rounding the current charge
up to 3,637,248 KiB and retaining the full 786,432 KiB remaining reserve gives
4,423,680 KiB under 4,718,592 KiB, leaving 288 MiB. The 1 MiB owner tail reserve
stays inside the ceiling. Fresh admission, host conditions and owned QEMU
identity/retirement checks remain required for any guest run. Adapter/owner
deadlines remain 2400/2520 seconds, log cap 32 MiB, with unchanged 2/1 GiB free
floors. No retry or VM is inferred from successful preparation.
