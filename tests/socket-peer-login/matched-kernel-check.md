# Matched frame and peer kernel qualification

## Current atomic-v3 qualification

Current raw evidence is `B/matched-peer-frame-atomic-20261026/build-02`
(`B` is defined below): both architectures passed, actual outer zero/312.17s,
qualification `7c8af86382b7df1a131cc9bf0cdaa2dadf87719e4d33a9dfa011ffaf2e259fef`.
Source base is 9ace; patch SHA256
`c1891d5ffe3823d9d7bfe9b3b47ba14fab590f8e8e12f2afb0d47b28cc2bb5f6`.
Both actual make statuses are zero with `leader reaped; group absent`, using
`ALLOC_TRACK=1 PROD=true`, x86 `LIMINE_MP=0`, ARM `LIMINE_MP=1`. Actual make
times are 143,143ms x86 and 95,824ms ARM. Both passed 18 frame/29 peer mutations.
The current original full manifest is
`B/matched-peer-frame-atomic-20261026-seal-01/complete/inventory.json`, SHA256
`d7764b47d4c617550ed67af5eee5167392f818ea51e884d1a6abaf3469acf118`.
Creation and two independent unchanged-original checks returned actual zero.

Both current complete source inventories hash to
`e0c63ebc9aa293a415cddb2385cc023ab9abb3c790b7d9b2df14ec9a58f381cb`.

| Architecture | Current ELF SHA256 | Current generated C SHA256 |
| --- | --- | --- |
| x86_64 | `162008b2cd4bde3cfa5110dacb8caa604c8e27b620a92e3cdec6ef51755dc9b7` | `1ac1984e66fc210b3049b3e35e93fa4fb922ebf57de734c9fff02e294ded1d34` |
| aarch64 | `1111f8d6451a0ab94361c3ebf006e9ceed62baea9dd395ac0a5c3caa7fb3a254` | `87166ca286e94f5cf9b827e1ffd09bc8c1b6aebf5994188de0b0e3e30a454855` |

The qualified bootstrap-03 source is
`20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd`;
binary `39108da8f5726becc6e36bba74fbe2489f4a80ca2b4dba7353d69282080ad44b`.
Current host controls receipt:
`3015da84db780224a58831b22c66a2991190148715bb1beb2207b1b04dad8558`;
recursive dylib closure controls:
`6ba455380aa5fc81545216767b7174ad2a9d4b1c9a70fbe3f3c2b641e21642`.
Maintained synthetic closure tests separately passed all nine cases at
`B/matched-peer-frame-atomic-closure-tests-01`: strict ff75/LLVM bootstrap
actual zero/4.66s, test executable zero/0.67s. They cover recursive and inherited
rpaths, intermediate symlinks, missing candidates, cycles and refusal cases.
The frozen implementation/test source hashes are
`503f30711a16017ef56a12555bf609dfb5ecb5bad4d0ec5ff18e3768caf6727c` and
`ca9b386e31bc3ccd92b02c91d3d8322b4778e844dc7735d3736620f0fd464346`;
the executable is
`accc1ec154bb4f195c3bb66dc3a68fd2feba4d94dafd8ff4b2906a525c41096b`.
The complete external bundle is preserved under the same base with
`-seal-01/complete/inventory.json`, SHA256
`35d4453d869d688d1d0a95782137f779e88cf79ba6531db51951e4d803e6e947`;
the unchanged original independent check returned zero.
Build-01 preserves actual x86 make zero followed by a control refusal for the
compiler's nested-u64 packing spelling; no ARM/overall pass was claimed. The
corrected check binds the complete expression, with uid/shift mutations and
barrier-order mutations. A separate retained-C replay passed without claiming
a new build. Fresh build-02 supplies qualification. Earlier refusals remain.

## Current selected copy and baseline

`B/matched-peer-frame-atomic-kernel-20261026` is closed at 91,792 KiB by
`du -skl`, within the 128MiB selected limit including metadata reserve.
Its format-2 receipt SHA256 is
`2d93f496c9f17a029eff5691070fb6093cad741380b28a87736f12ebfa35e5cb`.
The retainer requires the full original audit and successful original build
and cleanup statuses, derives four flags from actual argv and keeps all audit
pins. Actual retainer zero/14.96s includes original check zero/12,758ms.
Bootstrap was zero/5.42s using qualified ff75 V, private temp/modules,
production mode, `-nocache` and absolute LLVM without fallback.
Source `b264e9b53b5caa16d3cef88322d54fdf2ef1cc0f28b7485c45560dfe24830034`;
binary `e777fdca6c7cc36dbe0fb2a4d0729f448f71b67281e648d9e66ec0e704da728a`.
Selected full manifest:
`B/matched-peer-frame-atomic-kernel-20261026-seal-01/complete/inventory.json`,
SHA256 `3a36d8ec634fa43d416fa3a4ce0ba726eea35527dc8c1faac893faa0feab4a1f`;
two independent unchanged-original checks passed. Retainer host full manifest:
`B/matched-peer-frame-atomic-kernel-retainer-host-01-seal-01/complete/inventory.json`,
SHA256 `158a25e4c55eea1176b075a41988f75e95fb6223e2b61703eb4185f5be9a13a5`;
its independent unchanged-original check passed.

The fresh frame-only x86 baseline is
`B/frame-peer-baseline-device33-20261026/build-01`, actual zero/156.22s.
Qualification receipt/ELF/C hashes equal the first baseline below. Identical
before/after complete input maps hash to
`3f73b192d63460a827f0dcafce95521f4cd7dae847c310d0c3857b9715c61dd1`.
Its original complete manifest is
`B/frame-peer-baseline-device33-20261026-seal-01/complete/inventory.json`, SHA256
`b826fe4f36b1599c3bbb31c3d5749cae3e32b6944f2220f20ea14d60672b8fe9`.
Both independent original checks passed. No ARM baseline is claimed.

Atomic-v3 corrects the historical findings below: one locked
`proc.login_identity` snapshot precedes socket locks, and one packed atomic u64
tuple uses idle/connecting/connected/closed states. Compare-exchange grants one
stream writer; failure resets only connecting; close permanently retires.
Private tuple storage precedes a full barrier and connected publication. The
getter acquires state then loads a tuple into a stack record. Independent
review covered both atomic backends, FD/handle lifetimes and repeated/close
races. No allocation, free, escaped pointer or grace period is introduced;
increased socket size still needs measurement. `guest.v` has host declaration
qualification only: ABI/refusals, failure recovery, repeated connect, peer close
and 32 concurrent rounds. Native execution and
`ops,churn,cache,idle,apps,drag` remain required. Production stays uncommitted.

All current audits use unchanged
`B/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal`, SHA256
`fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`;
maintained source SHA256
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`.

## Historical evidence and subsequent refusals

The records below describe creation-time build-05, selected-copy and baseline
results. Their immutable original audits later correctly refused after observed
host device renumbering from 16777232 to 16777233. The baseline diagnostic found
device changes on all 1,754 entries; every other field, header, order and entry
matched. No cause is claimed. This diagnostic is not replacement qualification.
All old bundles, manifests, checkers and refusals remain unchanged.

The fixed `guarded-build-check.v` profile qualifies source
`9acefa77bee69247c837e97987a2377536aa41cc` plus the seven explicitly pinned
frame/peer source files. It is an audit profile for the retained checkout,
not a claim that later repository revisions were built. Kernel production
changes remain subject to guest performance and lifetime review.

Evidence is retained under
`/Users/alex/Library/Caches/vinix-codex/section14` (`B` below). Generated
outputs and complete inventories remain outside Git.

## Historical matched build

`B/matched-peer-frame-20261026/build-05` passed both architecture builds.
Its qualification receipt SHA256 is
`05ea81df65e801356fe4a5dbf185a914dd07b39f927508ec47d036580e02f65c`.
Both builds used `ALLOC_TRACK=1 PROD=true`, `LIMINE_MP=0` on x86_64 and
`LIMINE_MP=1` on aarch64; all optional test modes were zero. Each retained
`build.argv.json` records the full flags. Both statuses record actual exit
zero and `leader reaped; group absent`.

| Architecture | ELF SHA256 | Generated C SHA256 |
| --- | --- | --- |
| x86_64 | `b70d1e316d29cbc22368695667b41311ec88dd6aa75362e014f64d973033e6e4` | `c718dfa8eada968765e679fd15dbb7a0dc741634d468680ef590eaa61cf9562f` |
| aarch64 | `e805a73154d61503d6427f1ccc4d19b1eb9ec802ed38255e059e0b2bd1e83174` | `928c4999d3524052aff22526c3daa34c5bf242e7b58364b45e6bfd564ff59c9d` |

The driver checked the actual frame helper/call site/borrowed pointers and
all 18 mutated-C refusals, plus peer ABI/cached identity bodies and all 17
mutated-C refusals on each architecture. Exact defined text symbols reject
undefined, data, suffix-only and duplicate entries. The earlier build-04
refused an inlined peer getter's absent standalone symbol; build-05 checks
the getter body and actual linked syscall instead. Earlier attempts remain
in the complete bundle.

Host controls covered positive/nonzero probes, deadlines, output limits,
interruption, descendant cleanup and raw i32 waitpid/ECHILD ownership.
The final original host-controls receipt is
`a43665f0a59854e272981b59e93c52f32e602d101d957d09116751aeccf43666`;
the actual recursive tool dylib closure receipt is
`909b1793fbe6ed509273ac84a615450e8f1d41b43fbf10b120d2618cb79b7417`.
The maintained closure module binds literal/intermediate symlinks,
loader/executable/rpath resolution and selected Mach-O load commands.
System shared-cache install names and host OS provenance are recorded;
their unavailable cache bytes are not represented as retained files.

The original complete metadata inventory remains
`B/matched-peer-frame-20261026-seal-01/complete/inventory.json`, SHA256
`1be74ac86fd98743e6691e9d29e44a20f1476bbc2cb494d157f70de618fa4165`.
The original checker and a separate independent invocation both returned
actual zero with `FRAME-PAGE COMPLETE STATE CHECK PASS`. This is separate
from the older historical frame bundle whose original metadata seal now
refuses; see `../kernel-allocs/frame-page-check.md`.

## Historical selected consumer copy

`matched-kernel-retain.v` first requires the complete original audit, then
copies the seven sources, tracked patch, sorted source inventory, both
ELFs/generated C files and build logs as independent ordinary files.
It derives the four published build flags from the original argv and
requires the original successful build and cleanup statuses. The format-2
receipt keeps the exact original complete audit paths and checker pins.

The actual retained copy is `B/matched-peer-frame-kernel-20261026`,
91,772 KiB by `du -skl`, below its 128 MiB admission including a 2 MiB
metadata reserve. `kernel-seal.json` SHA256 is
`2acdf20a185bb8269cc254f8a0f675ad52da17e567adceb4462bf23dca98aa62`.
This selected copy does not replace the mandatory original audit bundle.

The retainer source SHA256 is
`e4b016729f587fcd937f3eedef5cea49c76807d18459ab9060f368c13b2eef40`;
its qualified host-02 binary SHA256 is
`2106fe79ba212d5040a69a14c12d9e2aced082cc7a981d1fd46c1cc6426ae197`.
Its actual original audit check exited zero in 85,809 ms. Host-01 preserves
the earlier compile refusal; host-02 compiled with the corrected ff75 V,
private temporary/module directories, `-nocache`, production mode and
absolute LLVM clang. No fallback compiler was enabled.

The selected-copy complete inventory is
`B/matched-peer-frame-kernel-20261026-seal-01/complete/inventory.json`,
SHA256 `4921ace3848464b7bc770757d7bd4b5556f6ab993e9aa2c6ccf4895c1221978a`.
Retainer host-01/02 complete inventory SHA256 values are respectively
`1a757165f1b61ff61818060135c42bb62e32c2fd8c2b96961cc5ec4e068c898c`
and `7e37a698c989c925be62828d15b4f41a15d883aa89361004d4e41281bc4eb428`.
All three original complete inventories independently passed. A premature
selected-copy check correctly refused while its manifest was absent; that
refusal log remains beside the subsequent completed-manifest passing log.

## First frame baseline

The fixed `--frame-baseline NEWOUT` profile pins the frame-only checkout,
proves its tracked kernel equals the same 9ace source base, binds four
frame source hashes plus three unchanged peer hashes, and independently
retains the controller source closure. It builds x86_64 only with the same
compiler, LLVM and flags as matched build-05. It checks the 18 frame
mutations and linked frame/syscall definitions; it makes no peer ABI or
aarch64 baseline qualification claim.

The fresh `B/frame-peer-baseline-20261026/build-01` build passed with actual
exit zero in 294,191 ms and `leader reaped; group absent`. Its complete
before/after source, compiler, dependency and environment inventories were
identical. The qualification receipt SHA256 is
`82b27fdc3cfb948db51dd88c9169a1a2031dc6f3bb6ac622575dd166ba041a9a`;
the x86_64 ELF is
`ca807b0d800c4f5ff13b8ca1e12dad4af022a49851f54f239af8d99ef969636e`
and generated C is
`1c7dc1b491c9e8f7debcb8bf68978614d5ca54f923c0c77ca19788fc556c920e`.
All 18 frame controls and exact linked frame/syscall definitions passed.
Its host controls receipt is
`7fea5db8fabe5af8a2c33cd9a5463548c9d8d974615f53e105fc2d9c1aafc165`.
The qualified driver source is
`638162259409a01b52dc1fc03ba47373fe9f657cd8b44ca1f17f3aa18ee2c358`;
its host bootstrap binary is
`f6c00fd2ae95c64edeeff2179de58c98717497186ed9d749da097b2aabdab3fd`.

The fresh complete original inventory is
`B/frame-peer-baseline-20261026-seal-01/complete/inventory.json`, SHA256
`503911b74414ef977bf6453a172ab25b44e5de4466164a66db9bd4d79e61bfcb`.
Both independent invocations of the unchanged original checker passed with
actual zero. An initial check supplied the manifest directory rather than
the required manifest file and correctly refused; that diagnostic remains
beside the successful `independent-check-final.log`. Actual disk use was
79,172 KiB for the dedicated state plus 12,824 KiB for its worktree, below
the 512 MiB limit. All original matched and selected-copy evidence remained
unchanged.

Guest `ops,churn,cache,idle,apps,drag` measurements remain required. A
frame4-versus-frame4/peer3 comparison isolates the peer change; it cannot
establish a seven-change delta against a pre-frame kernel.

## Historical peer publication review

The retained build-05 is historical build evidence, not permission to ship
the peer ABI. Independent source and both-architecture generated-C review
found no new allocation, free, escaped pointer or grace-period requirement.
It did find incoherent two-field process snapshots racing login-session
creation, and unsynchronized stream identity publication. The existing
`proc.login_identity` table lock provides the required coherent process
snapshot. At that point the corrected atomic lifecycle required fresh builds
and guest qualification. Current atomic-v3 build results appear above; target
qualification remains pending and the seven production changes remain held.
