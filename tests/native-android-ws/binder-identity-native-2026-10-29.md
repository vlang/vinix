# Binder identity native companion, 2026-10-29

The native companion for source fix `40724ff0184eb4f33a63324091ebfb26914e28bc`
passed fresh AArch64 compilation and shared linking with warnings treated as
errors. It consumes the [Binder identity framework](binder-identity-framework-2026-10-29.md),
manifest `739fc9c17258915b0ce7ee01fa3d9e03f47c9d4f4de05ef0c6178d624f8ff3c5`.
Focused host checks passed; ARM execution, ART compatibility and Maps/Google
authentication remain unverified for this coupled successor.

Artifacts are relative to `/Users/alex/.local/state/vinix/android` (`S`):

- Complete native output (`N`): `S/current-native-build-2026-10-29-binder-identity-r1`.
- Native producer controls (`A`): `S/native-binder-identity-build-2026-10-29-r1`.
- Complete focused host evidence (`H`): `S/auth-identity-checks-2026-10-29-r1`.

The producer receipt records revision `691c81bbecd9900d259c465b6ce92010574467f3`;
the retained exact working source hashes identify what was compiled:

| Input | SHA-256 |
| --- | --- |
| `account_service.v` | `de33aa1ae37bb430942bccd1f28f629519dd9d29da866898d78130fcbf7ae8bf` |
| `account_worker.v` | `db0f426089da7b3397662a1dcf93a1de37aa32979e4edfa746a63b01855a1c5c` |
| Native `bindings.txt` | `e3fa613993c1ca60aab021ebdbacc93dc71ae68e4bef3d112482f77c8ddeb95b` |
| Broker framework provider | `8a2baf5fbfbeffa873a9ee47abf69667b2a3f976c7bacac84f4f82de4be07d41` |
| `build-current-native.v` | `a468758d4957f66703836da209b901e1344a2f889b27c2df868630d97adc4d33` |

The matching retained bootstrap
`S/native-auth-worker-build-2026-10-29-r1/tools/bootstrap`, SHA-256
`87fdd3470d639f1456eae758da4555b3f402a3adceea7793893d0c932d86d12d`,
was reused because its retained builder source matches the current source hash
above. It compiled a fresh frozen builder and fresh current JNI/native inputs.
The checked `execvp` handoff replaces the bootstrap process; the outer guard
recorded one supervised process group, 75408. Complete source listings, before/
after hashes, compiler inputs, consumed headers and framework bindings remain in
`N`, together with the fresh generated JNI and linked native library.

Production passed after 29.160 seconds at 613,138,432 bytes peak sampled aggregate
RSS, below the unchanged 629,145,600-byte cap. Guard/child exits were zero, cleanup
completed and the time report records zero swaps. Limits were 600 MiB RSS,
300 seconds, 2 GiB observed shared-volume growth and a 1 GiB reserve. Observed
global growth was 109,838,336 bytes; it does not isolate producer-owned allocation.

Final host checks in `H` passed worker pthread/scoped-identity/ownership checks
with ASAN; service continuation, terminal replay, cancellation and isolation;
broker legacy/generic integration and nested wide identity ABI assembly; exact
JNI 64-bit-token/boolean-result generation; account-store/token mutation checks;
and the retained authenticator-base runner. Their original successful receipts
record zero exits and completed cleanup. Earlier service and broker-runner
compilation failures remain in the complete bundle; the named passes refer to
the final successful checks, not every retained attempt.

| Output | SHA-256 |
| --- | --- |
| `N/sha256.json` | `2a68a45164d830cb2b3cdfcc43b2e3590ff42dc15152041fea166cd6c8f58985` |
| `N/build.json` | `e43f3c32c9b410cc03772aeb2554a70881426fa0348e9ba9294ea12693aab452` |
| `N/native/libvinix-android-native.so` | `6a87d8c2fd003c55cb572ab397342d0c39aa54376ffe7a5a2ba2fa4592099eae` |
| `A/produce.guard.json` | `23ced6d85042af393c678c2c6fae7dc0dc11ab4531d3d17344af6a822fa2b4cd` |

Both closed native roots are bound by
`S/binder-identity-native-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`fe4c798250cd425c3c109754374fb563a7e6d401c85802155b84cdb4e6f26ac3`:
two roots, 1,758 entries. The separately closed host evidence is bound by
`S/binder-identity-native-checks-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`e3ca88fd196e6ee7fd6b3dc34cfaee5a0ed680c04bddcc351cf9d76678e20d18`:
one root, 524 entries. Both seals and separate fresh-process full readbacks passed.

Seal/readback guards retained 600 MiB RSS, 900 seconds, 64 MiB global growth and
a 1 GiB reserve. All exited zero with completed cleanup and zero swaps. Native
seal/readback took 0.313/0.230 seconds at 23,953,408/13,631,488 bytes sampled RSS;
host-evidence seal/readback took 0.137/0.172 seconds at 2,899,968/1,507,328 bytes.
Keep all original bundles unchanged; this report does not replace them.
