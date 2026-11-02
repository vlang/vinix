# Messenger Binder Maps media qualification

This profile gives Messenger a Handler Binder endpoint, an IMessenger wire path
and Message Parcelable/UID behavior. Five existing classes change and three
Stub/Proxy/MessageCreator classes are added: 2,112 classes become 2,115.
Messenger$1 explicitly removes two old methods and its captured Messenger field.
All five removal-count keys, exact field additions/removal and class order are
bound. Whole Handler, Binder and Parcel remain unchanged. Core is
`2166f55d7` / `23296f853`, producer `147d9c296`; the
[framework/native report](messenger-binder-pair-2026-11-02.md) records the pair.

The six-file overlay inherits `maps-usage-inactive-r1`, audits all 123 complete
inherited inventories and requires exactly 125 dependency seals. It appends
module 54 after 53 retained modules. Actual ancestry reaches the original
`maps-account-r5` inode inventory in 47 stages. Exactly five existing deployment
inputs and the framework manifest change. Only the JAR changes in the seven-key
headless input map.

The full framework audit admits exactly the eight selected classes. All 70
native-consumed canonical classes remain equal; Context and ATLLoadedApp retain
two exact raw formatting differences from canonical cloning, with the other 68
raw inputs equal. Native provenance remains its original broadcast SDK.
The complete native bundle, 91 origins, 92 inputs, 721 exports, production
sources, JNI, C, all 58 C/header inputs and 650-entry builder / 340-entry generator
closures stay unchanged. ContextImpl's manual JNI ABI and User/StatusBar classes
are also pinned. Historical complete bundles and their checkers remain required.

| Artifact | SHA256 |
| --- | --- |
| Prepared Usage parent | `8685761d98b7e3d395bde91d2ec2e7db9c23fa60aa4472aaa47d821d9ae2245c` |
| New SDK manifest | `e3d313ae3e51404da203344ef1a6db32a4aaf24fe01ac971a71fd69ae586aa85` |
| Retained native manifest | `e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b` |
| Qualified stager | `b15e22200fd2501c87ebf2356f66fc4d21d182ba85cebc5599d4ecd31e244d76` |
| Qualified kernel patcher | `0db22edb5e922830d9959621d90e735168aedefd18f3795c071e1b9dae4b9c60` |

Required tool checks passed on first attempts: serial V/C builds, stager selftests,
full SDK/native/header/helper audit, 47 receipt/profile checks, 40 FAT cases,
all prior tests plus real 123-root positive/refusal/full-byte tests through
node 122, actual ancestry, and discovery of 284 V / 408 C stager inputs and
273 V / 405 C patcher inputs. Both factories preflight and validate their merged
class set before all five pure target validations; writes follow only after
those validations succeed. Complete original/copy/recheck capture retained 862
inputs. The protected batch parent existed before invocation. Frozen sources
match the checkout; independent source and artifact review approved.

All 27 tool guards and children exited zero, reasons empty and cleanup complete.
Maximum sampled aggregate RSS was 532,217,856 bytes; detailed maximum
529,924,096 bytes, with zero swaps. Original limits remain: 600 MiB RSS,
300 seconds for builds/tests, 900 seconds for full audits, 1 GiB reserve,
512 MiB tool growth, 64 MiB seal growth and shell file cap 16777216. Compilers
were serialized while the owned VM remained stopped.

Evidence remains outside Git at
`/Users/alex/.local/state/vinix/android/maps-messenger-binder-tools-2026-11-02-r1`
and `maps-messenger-binder-inventory-batches-tests-2026-11-02-r1`. The eleven-root
producer seal is
`8d21336afbaf8861710b6872390da77c5f2ec4ad0a9413b7588056d4e8b089d6`,
including failed proof/fixture/builder attempts and the uncompiled proposal.
The original full native producer bundle remains separately required under
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
The closed tool and batch roots passed sealing and a separate fresh-process
readback: two roots, 12,859 entries, manifest
`6969df3fde12c3503ac28b8e74a73922daefb88d4932c2dec74fe3df49f14305`
at `maps-messenger-binder-tools-sealed-2026-11-02-r1/sealed/manifest.json`.
Both seal/readback guards and children exited zero, reasons empty and cleanup
complete under the original 64 MiB growth cap and 1 GiB reserve.

The source base before this tool commit is
`d0403c8d03d320745e64a2ca4db219ed9253f517`. Automatic preparation follows under
the original 5 GiB initial-space preflight and resource limits. This report
claims no Messenger ARM, account, checkin or current imagery result.
