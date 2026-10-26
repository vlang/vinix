# Combined account and WebView framework

The maintained V builder is `combined-account-webview-build.v`. Its `--self-test`
rejects unrelated class changes, omissions, substitutions, missing required
changes/additions, JAR member changes, and malformed or duplicate helper inputs.

The 2026-10-26 build passed assembly and canonical disassembly checks: 2098
baseline classes became 2101 classes, with exactly eight changed classes and
three additions. Every other class and every non-DEX JAR member retained its
SHA256. This validates framework construction; it does not establish ART
execution or Google account login.

- Source revision: `82bb77facbd9d784af11267c7d72880ac54b6941`.
- Builder source SHA256: `67d6094f355dd378e7f6432ef63138854ad6db13bcf855655a7e98317e81a773`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-framework-2026-10-26`.
- Bundle manifest SHA256: `798b574b811203313b185480ddfd9349bfc5b7e1863d96e99d9c1afca3be4dd2`.
- Output `api-impl.jar` SHA256: `296cb0bd9d16801322a18d40bca0facfb0593e50be47d424f199d02ceeb7e15f`.

The bundle retains builder/provider source closures, tool JARs, executable and
input hashes, command receipts, both canonical class inventories, and output
hashes. `combined-account-webview-build --check BUNDLE MANIFEST_SHA256` verifies
the complete retained file set. The pinned baseline is
`account-contract-authenticator-base-network-build-2026-10-26`, with manifest
`36a472320e71eb459896c1d52a8f211f475362fb2c6dada682870bf43b6a2b7b` and JAR
`9e643451d4d82fc3839c91415947f04d3726aa81967a784d4d26db63e2c88cb1`.
