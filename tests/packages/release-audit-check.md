# Release catalog audits on installed systems

Software's **Deployment → Check release apps** discovers the optional
`/usr/share/vinix-packages/applications.json` declaration and invokes the existing
read-only deployment audit. Administrator and standard accounts can compare
recorded installed metadata with the exact image lock without approval. The
report identifies its captured bytes by SHA-256 and shows missing, matching or
changed packages. Current trust and payload integrity have separate checks.

The action shares release discovery and literal-path selection with **Review
release apps**. Missing declarations or leaf symlinks preserve manual drafts.
Pending reviews cannot be replaced, late chooser replies are discarded, and
reload uses the captured filename. A metadata difference is a complete audit
result, not a failed installation. Changes still require a fresh review and
administrator confirmation. The image declaration remains the release baseline
when installed applications are updated.

The maintained [native catalog controller](native-catalog-check.v) now requires
release audit markers in its Software, persistent and installed modes. The
installed proof includes the declaration alongside PID 1, the service, sandbox,
Software and account/session tools. Each boot checks exact staged bytes, mode
0644, a single link, root ownership and the installed root's filesystem identity.
Cold observations retain the declaration's hash, size, UID, GID and mode too.

| Boot | Release catalog behavior |
| --- | --- |
| 1 | The real installer installs the image on a blank 4 GiB disk. An ordinary audit reports all three apps missing. One approved release review installs Hello, Counter and Memo. Both administrator and standard accounts obtain an exact match. |
| 2 | Retained staged declaration and installed metadata match. An authenticated upgrade to 1.1.0 leaves the 1.0.0 baseline intact; the audit reports version and metadata differences. |
| 3 | Repository payload directories are removed. Audits report the retained upgrade, an exact match after rollback, missing apps after uninstall and drift after verified-cache reinstall. |
| 4 | The same installed disk retains the declaration, reinstalls and private data. With repository payloads still absent, the ordinary audit reports the expected drift; Counter and Memo reopen their saved data. |

Every audit compares the configuration, declaration, catalog, trust history,
current generation link and state bytes before and after the read. No audit
asks for a password. Existing native launches, isolated user data, document
grants, signed updates, rollback, clean registration removal and cached reinstall
remain required. The ext2 retained-subtree mode runs the same four-boot workflow
as a regression; its `/usr` comes from the boot image each time.

Reproduce with the [installed-system instructions](software-installed-check.md#reproduction)
and current `native-catalog-check.v --installed`, on each architecture with new
state directories. Use `--persistent` for the ext2 subtree regression. A reviewed
compiler, verified native inputs, matching kernel/sandbox and the headless ui2
module remain required. Host controller hashing should use `-prod`.

These checks exercise real installation and package services with headless UI
trees. Boot firmware still loads the kernel and fallback initramfs from test
media. Production publisher enrollment, legacy/vendor catalog migration, full
graphical sessions and broader foreign-runtime/device/crash qualification remain
open in roadmap 14.

## Recorded results, 2026-10-16

Fourteen focused Software compile/run checks passed, including UI ASan/UBSan
with leak detection disabled. The maintained Software suite passed its complete
functional checks, all 27 allocation modes, both full Linux desktop target
typechecks and launcher checks. After warmup, 1,000 full/compact release form,
discovery, missing-file refusal, navigation and retirement cycles retain zero
tracked bytes. Existing audit decode/render/reader retirement checks also pass;
this does not claim whole-service or broker allocation freedom.

All sixteen target boots passed on fresh disks: four installed VJFS root boots
and four ext2 subtree regression boots on each architecture. All forty release
audit transitions passed with unchanged state observations. Each boot required
its workflow marker and guest-initiated QMP shutdown. Every installed boot also
required the declaration's exact staged hash, size, owner, mode and disk identity.
The V evidence verifier checks receipt artifacts, full initial/final disk hashes,
ten-entry staged proof documents and copied controller sources. The kernels
match the previous Software qualification; this increment changes no kernel.

Initial attempts exposed two fixture mistakes: expecting diagnostics to clear
after a deliberately incorrect password, and sending an extra x86 proof marker
to its display console instead of the serial harness. Both were corrected
without weakening the audit or disk proof. All final runs use unchanged final
product/fixture sources and new disks. The attempts and exact compiler, source,
staged input, generated program, receipt and log hashes are retained.

- [Host/guest summary](results/2026-10-16/release-audit-summary.txt), [fourteen host checks](results/2026-10-16/release-audit-host.json)
- [Software checks](results/2026-10-16/release-audit-ui.txt), [allocation checks](results/2026-10-16/release-audit-memory.txt), [sanitizers](results/2026-10-16/release-audit-asan.txt), [maintained driver](results/2026-10-16/release-audit-driver.txt)
- [AArch64 installed receipt](results/2026-10-16/release-audit-installed-aarch64.json), [fourth boot](results/2026-10-16/release-audit-installed-aarch64.boot-4.serial.txt), [QMP](results/2026-10-16/release-audit-installed-aarch64.qmp.txt)
- [x86-64 installed receipt](results/2026-10-16/release-audit-installed-x86_64.json), [fourth boot](results/2026-10-16/release-audit-installed-x86_64.boot-4.serial.txt), [QMP](results/2026-10-16/release-audit-installed-x86_64.qmp.txt)
- [AArch64 ext2 regression](results/2026-10-16/release-audit-persistent-aarch64.json), [x86-64 ext2 regression](results/2026-10-16/release-audit-persistent-x86_64.json)
- [Attempts](results/2026-10-16/release-audit-attempts.txt), [source/toolchain/artifact ledger](results/2026-10-16/release-audit-toolchain.json)
- [V guest invocation](results/2026-10-16/release-audit-guest.v), [host checks](results/2026-10-16/release-audit-checks.v), [evidence verifier](results/2026-10-16/release-audit-retain.v)
