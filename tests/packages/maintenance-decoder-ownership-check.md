# Software maintenance decoder ownership

Revision `3b5f265ece14a122844cf0e67e025a2db02f122a` releases the temporary
records used to decode cleanup reviews, deployment audits, and saved deployment
receipts. Successful reads transfer the decoded fields into a closeable
result. Rejected reads release the fields parsed so far, including any
partially decoded audit row list.

| Check | Baseline retained bytes | Fixed retained bytes |
| --- | ---: | ---: |
| Cleanup protocol, 1,000 complete and partial-invalid pairs | 240,000 | 0 |
| Software cleanup page, 1,000 cycles | 120,000 | 0 |
| Software maximum-size and empty cleanup navigation, 1,000 cycles | 240,000 | 0 |
| Saved receipt protocol, 1,000 complete and partial-invalid pairs | 208,000 | 0 |
| Software deployment saving, 1,000 cycles | 208,000 | 0 |

The earlier Software run recorded the cleanup page baseline.
[Earlier measurement](decoder-ownership-check.md)

The baseline deployment audit protocol and Software audit allocation checks
terminated before reporting a retained byte count. The fixed protocol retained
zero tracked bytes across 1,000 complete and partial-invalid decode and close
pairs. The Software audit retained zero tracked bytes across 1,000 decode,
detail, render, paging, and retirement cycles. All three protocol checks also
passed ASan and UBSan with sanitizer leak detection disabled.
[Cleanup](../../tools/packages/pkgprotocol/cleanup_test.v),
[audit](../../tools/packages/pkgprotocol/deployment_audit_test.v),
[saved receipts](../../tools/packages/pkgprotocol/deployment_saved_test.v)

The full host `distribution-check --software-only --direct-tests` run passed,
including the 4,096-generation cleanup navigation and deployment audit search.
The headless Software source overlay typechecked for AArch64 and x86-64 Linux.
[Software driver](distribution-check.v)

Both QEMU targets passed reviewed cleanup and deployment audit with retained
qualification kernels and freshly built package fixtures. AArch64
completed them in 18.2 and 46.6 seconds, and x86-64 in 43.2 and 80.4 seconds.
The guest drivers now enable heap tracking for both protocol fixtures. Their
existing CLI workflows also exercised reviewed deletion, ordinary-account
audit and snapshot saving, and authenticated deployment reproduction.
[Reviewed cleanup](reviewed-cleanup-runtime-check.v),
[deployment audit](deployment-audit-runtime-check.v)

The independent archive checker verified all 303 sealed entries. The
archive SHA-256 is
`9474b738b6ffd185574cd25d0b2abec2da61d453375648d08965dd44b04059a3`.
[Qualification archive](/Users/alex/.local/state/vinix/r14-cleanup-allocation-qjiJuq/qualification.tar.gz)
