# Browser diagnostic r10 — 2026-10-26

The r10 browser export could not be collected. The preserved `finished.png`
shows `BROWSER-GUEST exported status=failed` and a returned shell prompt, with
Maps' Sign in onboarding behind the terminal. This credential-free diagnostic
does not establish browser DOM completion or Google account login.

The unchanged strict collector exited 1 on the original UART:
`embedded archive frame at serial line=3490 prefix-offset=1 expected-chunk=0`.
The first chunk is interleaved character by character with GMS module-config
logging. The BEGIN/END headers declare SHA-256
`dbe3416416dc85f8de5d6289a9628105abf7609318c4a90646d6833afbd4f0d8`,
3,376,210 bytes and 6,595 chunks; that payload was never accepted or verified.
No collected-results directory was created, and the UART was not edited or
salvaged. Authority, syscall, browser and descendant-cleanup results inside the
unavailable archive remain unknown.

The frozen kernel's console/UART sources explain this corruption: console
writes call unlocked `uart.write`, while `syscall_kprint` holds a separate
`kprint_lock` around calls to unlocked `uart.putc`. These paths share no record
lock. Their reviewed source hashes match the retained kernel sources exactly.
This report changes no kernel code. The next diagnostic should suppress
unrelated Maps/GMS autolaunch before replaying the original strict export.

The prepared r12 runtime includes the explicit llvmpipe selection from
`76a8df84f`. Its run used frozen kernel revision
`577a2d8c29ba6d4a95a655d507ef38414d3b8c77`, binary SHA-256
`ee6aa1acb31f11b8abf16c4001149ccb92e8f8fe35d0106342bbdbad6e7e57fd`.
The kernel patch receipt verifies the preserved boot modules before and after
replacement. The host requested SIGTERM for its owned QEMU PID 52167 at
17:28:09 UTC, and the matching absence receipt records that PID's disappearance.

Preserve the complete bundles under
`/Users/alex/.local/state/vinix/android/`:

| Bundle or receipt | SHA-256 |
| --- | --- |
| `browser-probe-build-2026-10-26-r12/build.json` | `33d92e97c5621d092b195551a1c3689b4bfdc5290697495b66a660265593a271` |
| `browser-probe-vm-2026-10-26-r10-llvmpipe/serial.log` | `07d587a7407ebee39e539073c0d0fb33198b2c98a66d7c0d68c09c2ab9d30a62` |
| `browser-probe-vm-2026-10-26-r10-llvmpipe/finished.png` | `05286b8cb01628bef3839b3c26231ad8cdf9afeb19feea6830f9dfda6800ba92` |
| `browser-probe-rejection-2026-10-26-r10-llvmpipe/collector.log` | `69a4e9647c3d38d0907ea8de840615ba4314472f8b88c4d892afd3e8742e1294` |
| `maps-account-collect-r2` | `f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e` |
| `browser-probe-evidence-2026-10-26-r10-llvmpipe/manifest.json` | `c129284909e3ffbaf84b1873357f252b222b5f1df3ec76e7f7996b82855f52d0` |

The rejection metadata retains the collector command, exit status, diagnostic,
self-test output and reviewed UART source pins. All five collector protocol
self-tests passed, including embedded-frame rejection and bounded diagnostics.
The seal covers 10 roots and 4,913 entries: the original VM, prepared r12,
`procfs-overflow-2026-10-26-r1/kernel-aarch64`,
`account-authority-build-2026-10-26-r5`,
`unix-recvmsg-flags-build-2026-10-26-r3`,
`maps-host-tools-optimized-2026-10-26-r1`, its sibling SHA-256 inventory, the
collector executable, rejection metadata and the seal itself. Keep every root;
these concise pins cannot replace the complete evidence. Seal creation's
check and the separate full recheck passed; their logs are retained as siblings
of the seal directory.
