# ComponentName parcel Maps media qualification

The unchanged Messenger ARM fixture found ComponentName's missing parcel
implementation. Core `eb467cd5a` supplies six parcel methods, a CREATOR field
and one fieldless VinixComponentNameCreator. Producer `38a56c93a` builds the
SDK: 2,115 classes become 2,116. All 23 original ComponentName methods, both
private final String fields and class metadata remain equal, including the
manually consumed String/String constructor and both getters. The
[framework/native report](component-parcel-pair-2026-11-02.md) records the wire
and null behavior. Whole Handler, Binder, Parcel and ContextImpl remain pinned.
This ordinary append-only receipt omits Messenger's removal keys; the new
checker explicitly rejects either removal key, including an empty map.

The six-file overlay inherits `maps-messenger-binder-r1`, audits all 125 complete
inherited inventories and requires exactly 127 dependency seals. It appends
module 55 after 54 retained modules. Parent ancestry reaches the original
`maps-account-r5` inode inventory in 48 stages. Exactly five existing deployment
inputs and the framework manifest change. Only the JAR changes in the seven-key
headless input map. Existing profiles and complete historical checkers remain
unchanged.

The complete framework audit admits only ComponentName and its creator. All 70
native-consumed canonical classes remain equal; Context and ATLLoadedApp retain
two exact raw formatting differences from canonical cloning, with the other 68
raw inputs equal. Native provenance remains its original broadcast SDK.
The complete native bundle, 91 origins, 92 inputs, 721 exports, production
sources, JNI, C, all 58 C/header inputs and 650-entry builder / 340-entry generator
closures stay unchanged. Historical complete bundles remain required.

| Artifact | SHA256 |
| --- | --- |
| Prepared Messenger parent | `e72282b9881ba4b82a053aa89c3e3b96383c7ee25cad637d5421b50717adff1a` |
| New SDK manifest | `79d78a512ac764807a2ecd3ca39317a5030e133f3749c0dd349c037482dcd512` |
| Retained native manifest | `e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b` |
| Qualified final stager | `ba5fec4b21052c6267d47fb56f5b48b91cdbe73edc914b6098b17fecabe5b147` |
| Qualified kernel patcher | `7ce82d80634a2108249b0a42dc4b1fd9c75c2bc8a07d8ee9db1be2d5d4da8fbd` |

Required checks passed: serial V/C builds, final stager selftests, complete
SDK/native/header/helper audit, 48 receipt/profile checks, 41 FAT cases,
all prior batch tests plus real 125-root full-byte positive/refusal tests
through node 124, actual ancestry, and discovery of 284 V / 408 C stager inputs
and 273 V / 405 C patcher inputs. Complete original/copy/recheck capture retains
862 inputs. Frozen owned sources match the checkout; the protected batch
parent existed before invocation. Independent source review approved.

Final review aligned this new stager's startup preflight with the explicitly
required 5 GiB minimum. Historical stagers and the internal 512 MiB cumulative
growth budget / 1 GiB reserve remain unchanged. Initial source
`f92cdf3f889e248af9f67ac4947dc5e50a862b3e6bf0285bf1ad673b63d2af4b`
and its successful checks are preserved. Final source
`1596404f1ec4808c4dcf59e6a9a9014b1abda28dd737b3f1652d8ae64f9f0d5a`
was regenerated and passed selftests and the complete framework/native audit
again. The final executable is in `stager-project-r2`.

All 33 tool guards and children exited zero, reasons empty and cleanup complete.
Maximum sampled aggregate RSS was 540,835,840 bytes; detailed maximum
538,361,856 bytes, with zero swaps. Maximum observed shared growth was
421,777,408 bytes; minimum free space was 3,832,614,912 bytes. Original limits
remain: 600 MiB RSS, 300 seconds for builds/tests, 900 seconds for full audits,
1 GiB reserve, 512 MiB tool growth, 64 MiB seal growth and shell file cap
16777216. Compilers were serialized while the owned VM remained stopped.

Evidence remains outside Git at
`/Users/alex/.local/state/vinix/android/maps-component-parcel-tools-2026-11-02-r1`
and `maps-component-parcel-inventory-batches-tests-2026-11-02-r1`.
The sixteen-root producer seal is
`4602a6e129564ff69905cc05a1ba619b5471b88ccfc5acbfdc99b5a0bb3b118a`.
The original full native producer bundle remains separately required under
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
The closed tool and batch roots passed sealing and a separate fresh-process
readback: two roots, 13,510 entries, manifest
`9fea6875f80e23d5d10606b5ec08ff0ff4a26e62d75d61261d63cdf73266e4b3`
at `maps-component-parcel-tools-sealed-2026-11-02-r1/sealed/manifest.json`.
Both guards and children exited zero, reasons empty and cleanup complete under
the original 64 MiB growth cap and 1 GiB reserve. Independent final artifact
review approved every guard, tool identity and retained-source comparison.
The checkout revision observed after qualification was
`22bda21a007fdafb790f0d4bec52497cbc4e0b52`.
Source and tool qualification are committed as
`b8d9473eecd1359fb700692a82aa04704b75c29d`. The authorized automatic preparation
attempt retained the original 5 GiB initial preflight, 4 GiB outer growth,
512 MiB internal growth, 1 GiB reserve, 600 MiB RSS and 900-second limits.
Its outer guard refused startup with 3,836,055,552 bytes free, below the
5,368,709,120-byte reserve-plus-growth requirement. The receipt records exit
125, child exit -1, reason `disk growth budget`, PID zero and no supervised
processes. `cleanup_complete` is false because no child started. The stager
was not invoked, its log is empty and the intended
`/Users/alex/.local/state/vinix/android/maps-component-parcel-r1` output is
absent. No image, ARM, Google account, checkin or current imagery result exists
for this successor. No retry is permitted until at least 5 GiB is available;
no limits were relaxed and no closed artifacts were removed.

The preserved attempt is
`/Users/alex/.local/state/vinix/android/maps-component-parcel-preparation-2026-11-02-r1`.
Its `prepare.guard.json` hashes to
`3c03bcb0f8070203fd8a20b4f16eea7c72e8dba775a1898f7dd2fce5c574d183`;
empty `prepare.log` hashes to
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Qualified tools and all producer, initial-source, historical and failed-attempt
evidence remain complete and closed for the eventual retry.
