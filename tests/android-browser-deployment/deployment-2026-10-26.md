# Maps browser deployment preparation, 2026-10-26

Host reconstruction passed. This prepares the protected browser closure for
Maps and Google Play Services; it does not verify Google account login.

Source changes: `ccd77a135` (mandatory injected bundle and CA pins),
`7c9d9dda4` (deployment builder), and `0f7e6e499` (musl ABI verification).
The build captured repository HEAD `577a2d8c29ba6d4a95a655d507ef38414d3b8c77`
with exact live source hashes in its retained `source-inputs.json`; the ABI
change was committed immediately after the successful build. Imported Maps
stager source is retained independently in the artifact.

Complete audit bundle, outside Git:

`/Users/alex/.local/state/vinix/android/maps-account-browser-deployment-2026-10-26-r6`

| Artifact | SHA256 |
| --- | --- |
| `sha256.json` | `5b634ad800523588729d70270e7612f1fa32b153ae57578916eae28d8dff116a` |
| `build.json` | `e4160962f3212ca72b84c0c0609b6cecdaf6fcc15c6a0448aa7a4b274551cdca` |
| `source-inputs.json` | `5d4845649458f7fabe005de07c68f411793ec5cc159bb465b2b73a473ae2446a` |
| `payload-files.json` | `958f96ff554757b7a14d4002341dfb87a4898dce7d6b160152c30ceeb7da4e94` |
| `musl-abi.json` | `b09936e93b3c9de2ac102a586236551cb91131bcc4fdfd82dfc047ca71f75d92` |
| `manifests/maps.manifest` | `67dbaf1b6c7b62cb5f9e739bbccb32ca616059875fb290a248c4ec325f40891f` |
| `manifests/gms.manifest` | `ac3f534bdeaad7480ca050453df1f95252afd32e4aecae4ed6be11199c03df69` |

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

All five host test suites passed (24 test functions). Coverage includes archive
path/link rejection, exact dependency providers, font parsing and decompression
bounds, manifest identities, search-path exceptions, symbol types/data sizes,
weak imports, COPY data, symbol versions and malformed ELF tables. Host V:
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
