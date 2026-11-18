# G13 device-control completion

Context retirement and threshold heap collection both issue a G13
`DestroyContext` command. The previous wait could accept a matching read
pointer after a channel fault or concurrent with a manager stop. Vinix now
uses one wait for both callers. It checks that the manager is running, the
channel is healthy, both ring indices are in range and the host write pointer
still matches the published token. Asahi revision
`bed544bdf93a496ebf70ba180923bab12b6e01cf` holds the TX channel lock from send
through acknowledgement for both commands.

On failure, a published context stays pending and mapped. Its command is
never replayed. Heap collection keeps both captured prefixes reserved.
Corrupt ring snapshots latch a channel fault for the firmware worker.

Both new regressions reproduced premature release on baseline
`220babb38e2d9d192931ba39335653519fd924d1`. ASan/UBSan passed 4,752 context
retirement cases, 1,008 deferred-context cases, 768 heap barrier cases and
22 compiled negative controls. Coverage includes both firmware ABIs, ring
wrap, an invalid read or write index, an unexpected in-range write index,
a latched fault and a manager stop at completion. The FwCtl and G13 failure
fixtures also passed, alongside 79 local contract tests and 122 reference
checks against the archived Asahi sources and m1n1.

Isolated AArch64 and x86-64 production kernel builds passed. Generated AArch64
C confirms that both callers validate completion before releasing ownership.
The allocation scan found the same 176 allowance findings as the baseline,
with identical counts by source file and warning kind.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-device-control-completion-20261119.1SWkf5/`.
The `bundle.tar.gz` SHA-256 is
`846a5a7c9a7de24f05fd392aa72bc7474ac3453550396de22f8eebde8bc2c22d`.
Native M1 firmware validation remains open.
