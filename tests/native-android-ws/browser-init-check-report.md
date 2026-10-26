# Browser transport initialization checks

Source `16f020ef0` adds bounded numeric diagnostics for browser transport
initialization failures and the production-extracted checker. Parser source
`bcc303f81` accepts only canonical, bounded stage/code/detail/loader records;
`483252869` requires the exact sealed browser client DSO in Maps deployments.

The checker passes 17 startup cases and two logging-boundary/privacy cases in
normal and AddressSanitizer builds. Five compiled negative mutations fail as
expected: bypassed descriptor guard, missing close, wrong symbol index, overwritten
errno and omitted diagnostic. Success remains silent. Raw loader strings never
enter the diagnostic or public receipt.

Complete evidence is retained outside Git:

- Bundle: `/Users/alex/.local/state/vinix/android/browser-init-check-2026-10-26-r1`
- `sha256.json`: `06856816bec54f0344e7be007b2b95aba31c5dc02f02d40d723657dddbe176fc`
- Independent full inventory audit: 17 files, PASS;
  `/Users/alex/.local/state/vinix/android/browser-init-check-2026-10-26-r1-peer-inventory-audit.json`
- Pinned V compiler: `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`

The run captured base revision `483c405316a506b9cea89e099a94e43ef1f7a605`
before the source commit. Its retained inputs match these committed source hashes:

| Input | SHA-256 |
| --- | --- |
| `nativews/webview.v` | `a41bacd6b18a0332daca5e0ccd2beb324d1f6ac5f2acccd81feba695607f7859` |
| `nativews/account_service.v` | `5a9af144d2d8f16c1a9a67a452d022892142e8db1711fe5d751310e85837a858` |
| `check-browser-init.v` | `1c49c4e8a8da1f21da13dcee6386363312a34fbbe3476d2ac546f9d9e29ab190` |

The unchanged maintained `build-maps-account-guest.v` also built fresh static
AArch64 controller role r6. Its host self-test passes, including bounded numeric
browser diagnostics and mandatory browser client checks. The build captured
revision `1c6a46a51dcb1b342c3d6aaea4f0f532a28e6adc`, including the parser and
mandatory client commits above.

- Bundle: `/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r6`
- `sha256.json`: `5a46182682b5f3c9bf47478ab0fcfc9f9dd40f8aeee589851765df8458776773`
- `bin/maps-account-guest`: `39dc0055afa1360b25e84cec7073e67d732b21d8d168fd6eb1d7c7587a20f6f9`
- Retained `maps-account-guest.v`: `c1ca6eb726a41f3a78dcee8853f447921139ac727c48ee9f66b383b0f137940a`
- Independent full inventory audit: 3,100 files, PASS;
  `/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r6-peer-inventory-audit.json`

These are initialization, parser and deployment-input checks. They do not establish
successful Google account authentication or Google Maps rendering.
