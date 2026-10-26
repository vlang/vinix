# Maps browser deployment preparation, 2026-10-26

Host reconstruction passed. This prepares the protected browser closure for
Maps and Google Play Services; it does not verify Google account login.

Source changes: `ccd77a135` (mandatory injected bundle and CA pins),
`7c9d9dda4` (deployment builder), `0f7e6e499` (musl ABI verification), and
`b12359ea7` (bind ABI tables to unique loader mappings). The final build captured
repository HEAD `b12359ea77841e482677ede71d5ad231f5985ff3` with exact live
source hashes in its retained `source-inputs.json`. Imported Maps stager source
is retained independently in the artifact.

Complete audit bundle, outside Git:

`/Users/alex/.local/state/vinix/android/maps-account-browser-deployment-2026-10-26-r7`

| Artifact | SHA256 |
| --- | --- |
| `sha256.json` | `bc9f6e776d0c81bb1bca160ab1e4289e31db9f2a05983e00ba0fcb42be86244d` |
| `build.json` | `14b91a03eac6eaf5cfabe10c14ec0ca81503f92347ce6dfc0ab3eb29aa95b8b2` |
| `source-inputs.json` | `cbb50ee8bb100f55ed51b2e332df7855bbd810fbe602e359bd92503d97406df5` |
| `payload-files.json` | `958f96ff554757b7a14d4002341dfb87a4898dce7d6b160152c30ceeb7da4e94` |
| `musl-abi.json` | `b09936e93b3c9de2ac102a586236551cb91131bcc4fdfd82dfc047ca71f75d92` |
| `manifests/maps.manifest` | `67dbaf1b6c7b62cb5f9e739bbccb32ca616059875fb290a248c4ec325f40891f` |
| `manifests/gms.manifest` | `ac3f534bdeaad7480ca050453df1f95252afd32e4aecae4ed6be11199c03df69` |

The previous complete R6 bundle remains sealed at the sibling `-r6` path, with
inventory seal `5b634ad800523588729d70270e7612f1fa32b153ae57578916eae28d8dff116a`.
Review found that its ABI checker trusted section file offsets without proving
that they describe the loader's table bytes. R7 adds that proof and passed with
the same pinned inputs. The payload inventory, ABI receipt and both manifests
are byte-identical to R6.

Pinned input receipts:

- Base runtime manifest: `0321ddd8829dbd59ccb713ad2ada0074708b68820929fdc9546ecdd0704b2617`.
- Addon build: `2972666ece11534e4a57e5971b109ce64ba38788ec4ec046e28b2d217100a443`.
- Cookie-engine build inventory: `3c0a6407fdb54389771a949f170bc42d97bee4d82a0e3abb1e22341c040b31c2`.
- Engine: `99d18add16b75657dea30e3f792532252fae6c626521afe1f167e8911473d221`.
- Compiler sysroot libc: `293be7050415dac10c0ac4595764e2d9d79f8c5e42f43095acbfbfef42f2f6a9`.
- Runtime musl and independent `lib/libc.so` copy:
  `a51759ae98460199928655e59ab2843b8b7e8af6620c7e141e1fce1f107bf9aa`.
- External CA data: `028fca5150ee1915c4474489985d55c54fceaa680c754cc8d1301734f01b2232`.

The builder resolved 229 pinned APK packages and materialized 1768 package
files. It added the final engine, fontconfig, bitmap-font index and musl alias.
Every ELF passed the AArch64/musl parser, exact search-path policy and protected
dependency closure check. The engine's compiler requests `libc.so`; bounded
unversioned-symbol checks against compiler and runtime musl passed, including
the executable's COPY data symbols. The alias uses the exact runtime musl
bytes, independently copied rather than linked.

All five host test suites passed (26 test functions). Coverage includes archive
path/link rejection, exact dependency providers, font parsing and decompression
bounds, manifest identities, search-path exceptions, symbol types/data sizes,
weak imports, COPY data, symbol versions and malformed ELF tables. ABI regression
fixtures also reject alternative section copies, duplicate and partial LOAD
mappings, zero-fill overlaps and symbol spans crossing file-backed bytes; valid
adjacent and empty LOADs remain accepted. Independent mapping review passed.
Host V:
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.

Maps and GMS manifests bind exclusive principals 10012 and 10013 to separate
private app data directories. The stager consumes `payload/`, installs the
manifests under `/opt/vinix-maps-account/browser/`, and must preserve protected
ownership and enforce readonly leaf modes after original-inode collision
preflight. Complete artifact inventory and all payload files are regular files.

`guest_executed`, `login_verified` and `sandbox_qualified` remain false.
Production retains WebKit sandbox enforcement; no CPU rendering or diagnostic
environment settings were added. Guest startup, browser UI and actual Google
authentication require separate runtime evidence.
