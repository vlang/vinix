# Android device credential query

Source baseline: `c19b8a52983f8c76667d9dff66506035a1c9b87b`.
The bounded GMS phenotype audit found a required call to
`KeyguardManager.isDeviceSecure()Z` after its currently failing AssetManager
locale call. The qualified stable-display SDK has no such method.

The provider appends one public Java instance method returning false. This
runtime has no Android keyguard PIN, pattern or password enrollment or
credential backend. False reports that unconfigured Android device-lock state;
it neither grants authentication nor describes Unix login/account credentials.
Desktop password login remains a separate authority (see
`tools/accounts/loginchannel/channel.v` and `desktop/login_session.v`). Android
credential-protected storage currently models app directories, not enrollment.

The original four methods and all class metadata remain byte-for-byte intact.
In particular, the legacy unconditional `isKeyguardSecure()` true is preserved
and is not used as evidence of device credentials. KeyguardManager is absent
from the current 70-class native consumption set; no native declaration,
binding, helper, field or class is added. The full framework builder registers
the same provider after stable-display support. This contract must be extended
if Android credential enrollment is implemented later.

Focused V checks passed 29 malformed/repeated-input refusals before writes and
six semantic/ABI mutation controls, including true, legacy delegation, native,
static, retained access and field changes. API-28 assembly and two DEX
roundtrips preserve the four old methods, exact new query and single-class
scope. Independent read-only source review passed. The checker does not
emulate Android security state; the signed ARM fixture qualifies the real
system-service invocation separately. No full SDK/native build or VM ran in
this source qualification.

Complete frozen sources, malformed cases, Smali, DEX, logs, input/tool hashes
and guard receipts are at
`/Users/alex/.local/state/vinix/android/device-secure-source-check-2026-11-02-r1`.
The input/output receipt SHA-256 is
`e8fe34087fb026820a4fc500d9c29fd60446e836ec952e2181797d39000381f5`;
the complete SHA256SUMS digest is
`435f23e9f32a1a60b7e7b52b06c26f1aadd25ef885d22dc00d246a8cb2bb70ab`.
A first manifest attempt inadvertently included itself; its failed check and
bytes are retained, and the corrected manifest excludes only its own file.
Fresh-process checks of the corrected manifests passed.

| Artifact | SHA-256 |
| --- | --- |
| Provider | `8e2a2bfeec96d13f394ba83ceaf6d558bd8a0d6638c8120a43b3a1169260fb3c` |
| Full framework registration | `9aeb45380e61252b9ec1bf2a8b6c8d3a553b2e123313e649e3bbdf607a4e27c3` |
| Raw KeyguardManager | `935ea7fa6ea194eafd55a3bb9bd7fd9e445699dfb26fbc67eb9c7f423224c3ae` |
| Canonical KeyguardManager | `c21625a68268b19a02910b534dcf5f396d00523d3faab45699ecefabd6c44d46` |

The checker compile and source/DEX run exited zero with cleanup complete under
600 MiB aggregate RSS, 300 s, 512 MiB observed disk growth, 1 GiB reserve,
4 MiB output and shell file-cap 16777216. Their sampled aggregate RSS peaks
were 313,163,776 and 222,593,024 bytes; the source/DEX run took 8.286 s with
20,008,960 bytes observed growth. Detailed process reports recorded zero swaps.
All source and tool pins were rechecked at completion.
