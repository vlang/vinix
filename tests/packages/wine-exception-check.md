# Signed Wine vectored exception continuation, 2026-11-12

Source baseline: `f554e805985992072341732d54780beaff01192f`, plus the tracked
patch and new-source snapshots in the external evidence bundle. This continues
the [trampoline unwind checkpoint](wine-unwind-check.md).

The real V Win64 console probe now exercises Wine's actual Windows exception
dispatch through the signed package boundary, as uid/gid 1000 on both native
x86_64 and translated AArch64. No kernel, sandbox permission, Wine instruction
patch or translator change is introduced by this checkpoint.

Two vectored handlers and three continuable `RaiseException` calls check
first-handler priority, continue-search ordering, exception parameters and
continued execution after handling. Removing the first handler changes the
observed software sequence from `1`/`12` to `2`.

The same executable allocates separate code/data pages as RW and seals code RX.
Its AMD64 `mov eax,[rcx]; ret` reads 17 while the data page is readable. After
`VirtualProtect(PAGE_NOACCESS)`, the actual fault must report an access violation,
a read, the matching instruction/data addresses and the expected private page
protection. The handler changes saved RAX to 42 and advances RIP past the read;
returning 42 proves context restoration and continuation. After removing that
handler, a second fault must return the fallback handler's distinct value 84.
Both registrations must report successful removal. Deferred cleanup calls
`VirtualFree` on both pages before the later READY marker. This is a bounded read-fault/vectored
exception check, not stack-based SEH unwinding or arbitrary signal coverage.

All fixture logic and instruction generation are V. An opaque foreign scalar
binding retains MinGW's exact `LONG` callback type; V copies a four-byte result
into it after checking its size. Final generated C passes MinGW compilation
with `-Werror=incompatible-pointer-types`. The earlier `int` callback mismatch
and intermediate compile failures remain preserved. Generated C shows the
software record and parameters on the stack, with no V allocation in either
handler. No measured retained-allocation or Windows resource-leak claim is made.

Fresh `pe-01` passes complete original compiler/MinGW inventory comparison and
retains the new source, generated C, PE, map, literal commands and receipt.
Both fresh prepared runtimes admit that receipt before and after construction.
`native-x86-01` and `native-arm-01` pass signed execution, existing image and
W^X checks, private prefix/socket checks, outside-write refusal, natural process
retirement and the existing lease-release check. Independent `retained-x86-01`
and `retained-arm-01` pass; ARM explicitly requires the pinned fork-safe
translator. Existing Wine initialization warnings and wineboot's refused
network operation remain in the logs.

The native fixture now requires each new success marker once. The independent
retainer additionally requires exact line matches in order. Four new evidence
controls remove either marker, duplicate the read-fault marker or swap their
order. Their requested retained output must remain absent at the expected gate.
The complete matrices pass **55 x86 refusals and 64 ARM refusals**, each across
four shards. Every shard admits original and copied baselines. Both coverage
checks confirm complete, unique assignment and unchanged shared inputs. The
collection checker's baseline, exact retry and nine refusal controls also pass.

Raw evidence is retained at
`/Users/alex/.cache/vinix-wine-exceptions-20261112`. The parsed-source snapshot
tool preserves admitted source bytes and their modes at snapshot time, including
paths outside the compiler directory, and rechecks source-list and native-inventory
hashes. Both runs preserve 491 files. Existing output and a missing admitted
source refuse; the latter creates no snapshot output.
These copies do not replace original namespaces for historical auditors.
Selected current host-tool/firmware bytes are retained separately in that
workspace. Complete unchanged compiler, MinGW, distribution/translator,
sysroot/GCC and kernel inputs remain in the
[pinned-input bundle](wine-forksafe-retention-check.md); keep both bundles.

Graphical Wine, broader exception/signal and stack-based SEH compatibility,
detached-server lease supervision, complete corresponding source and release
acceptance remain open. Section 14 remains unchecked.
