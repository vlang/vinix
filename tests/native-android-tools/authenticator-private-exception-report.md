# Private authenticator exception diagnostics, 2026-10-29

The Maps account run reached authenticator dispatch and returned terminal error
1 before offering an interaction. `AbstractAccountAuthenticator` mapped caught
exceptions to that error without retaining the throwable. Its handler now writes
`ANDROID-AUTHENTICATOR-EXCEPTION` and the stack trace to stderr. The broker keeps
stderr in its private log; public account receipts retain only finite numeric
diagnostics and the private log's hash. A catchall around diagnostic output
preserves the original error mapping when logging itself fails.

`framework_authenticator_private_exception()` replaces only that method in an
existing canonical class. The checker passed method-only preservation,
idempotence, missing/duplicate-method and wrong-class controls, its original
permission and fourteen-slot dispatch surface checks, and DEX assembly. The new
source runner compiles exact relevant providers and helper function bytes from
retained originals, avoiding unrelated Android tools. Optional fresh output
retention preserves the assembled DEX without removing any check.

The signed ART fixture APK also assembled and passed signature verification.
Its new probe captures the existing four exception-category dispatch tests,
checks their synthetic stack traces, and verifies that a missing stderr sink
still delivers exactly one original error-1 response. **The updated fixture has
not run on ART with the new framework.** These checks do not establish the cause
of the real GMS failure or successful authentication. Independent source review
approved the handler registers, catch ranges, mapping and isolated check scope.

Evidence is under `/Users/alex/.local/state/vinix/android` (`S`), in
`authenticator-private-exception-check-2026-10-29-r1` and
`authenticator-private-exception-api-check-2026-10-29-r1`, with their sibling
`-controls` directories. The fixture records checkout revision
`c120651f737d5fb2c57b4d4e50f92b7e00a9399a`; exact modified working sources are
retained and pinned. Final identities:

| Artifact | SHA-256 |
| --- | --- |
| Framework generator | `ed21027dc0a356b98c52135264acf99e3e1d7f08fbd1be5fab09e8dbed6b36d1` |
| Checker | `05b7d35a9ca988f4771f4342466dcbdd998122bf4bc4bbe9454536a90a2c6c5d` |
| Isolated runner | `f250590e778b2f0f8239c46c2f173728f9fa0eb31833757e7e1c9bfc0a628053` |
| ART fixture generator | `b1e3bd24c8da621e0ea8e94505f413d67e1d67e2f2b5cb50ead133c8e12733be` |
| Final `isolated/receipt.json` | `98f57b06912d05a26641751f24e6f2d4cc7b73bb4cf156c3cfd629f83f8b688f` |
| Signed fixture APK | `c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941` |

| Check | Seconds | Peak sampled aggregate RSS, bytes |
| --- | ---: | ---: |
| Isolated runner compile | 3.316 | 335,806,464 |
| Final checker compile, surface checks and DEX assembly | 9.378 | 195,543,040 |
| Fixture generator compile | 3.213 | 338,591,744 |
| Signed fixture APK build and verification | 5.570 | 158,613,504 |

All passing commands exited zero with complete cleanup and zero swaps, under
600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared-volume growth and a
1 GiB reserve. Retained earlier attempts include missing module-path compilation,
the full-module RSS guard at 637,190,144 bytes, a monitor deadline failure, and an
isolated compile that still included unrelated account providers. The final
runner extracts the exact account-class function; no guard was raised.

Complete in-place seals and separate full readbacks passed. Their manifests are
at each evidence stem's sibling `-sealed/manifest.json`:

- Original checks, failures and fixture: two roots, 277 entries,
  `31d257c36ead6658d61a3647fbb20c32b94ab90ad0b3bab6a690ae2decb16c53`.
- Final method-only API checks: two roots, 32 entries,
  `498c7f02e7393726e726023b8ee8118f0930d297c2608149655f6649bf3719c4`.

Seal controls remain outside those closed roots in sibling `-seal-controls`
directories. Neither bundle qualifies a guest run of this diagnostic change.
