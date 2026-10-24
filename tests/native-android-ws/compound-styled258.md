# Styled CompoundButton paired regression

Compound262 passes the paired guest regression. Baseline247 passes the
existing default/null/custom checks, then fails the new neutral-style
assertion. Fixed262 logs `DEFAULTS-PASS`, `NULL-PASS`,
`NEUTRAL-STYLES-PASS`, `NULL-DEFAULT-STYLES-PASS`, `STATEFUL-STYLES-PASS`,
the overall CompoundButton `PASS`, and `BOOTSTRAP-READY`; it remains alive
for the full 30-second observation without an assertion failure or exit.

Both original suite rows retain `startup_failed` and
`functional_passed: null`. Fixed262 has `backend_ready: true` and
`process_exited: false`; its only failure markers are the existing
`Main.bB`/`Lnge;` `NoSuchFieldError` and `ClassNotFoundException: nge`.
The checker accepts only their two complete observed lines and preserves
the original classifier. Guest assertion success is reported separately.

The earlier compound258 and compound260 pairs both failed the fixed
runtime's first default assertion, before `DEFAULTS-PASS`. Their complete
bundles and strict-check rejections are retained. The compound260 diagnostic
identified a present framework resource, `btn_check_material_anim.xml`
(`0x010800dc`), whose drawable loaded as null: measured width 6 against
the unchanged default expectation 36. The repair restores the fallback
for this unsupported framework default while retaining explicit-null,
application-source, style and theme gates. No fixture assertions changed.
Diagnostic evidence is under `compound260-diagnostic-2026-10-24` in the
same external parent; its small completed inventory is
`cfbf5448edc24df5ed9727ca01a422112e87620b958837964df60a71668fb224`,
with serial `ad3fa5b67d01c465aa868f74b6db5a14a9728af5a362f1399eb5d621065d966d`.
That diagnostic makes no full-media seal claim.

Complete bundles are outside Git at
`/Users/alex/.local/state/vinix/android/compound{258,260,262}-2026-10-24`.
Each contains independent prelaunch and completed trees, raw streams,
screenshots, private media, source/tool closures and build/run receipts.

| Attempt | Complete inventory SHA-256 |
| --- | --- |
| Failed258 | `a279c5a2ea4dcd8aa83dc133e494647a2ec2fcb48d4c84d4bc3b22ce6de2f7a9` |
| Failed260 | `8aff60edc94e98df2edad4cbda8ef50cf013ab71b72ac3d1a6c92916b69c0173` |
| Passing262 | `266c69ebfe021eae6224cfefe920d39ec348a2d1b9c89bc310bc0c60cd837526` |

The baseline is `5577de6f3`, framework
`73a10513135f9e264df9afdc7139c5370d67016d864be82fe0d6b2adba1f459b` /
native `78893e6767c9398a7d6cb513f0f34b8536604afaa065e383f46cb98e9d003f37`.
Frozen 125-file framework and 83-file native maps plus exact texts limit
the changes to `framework_check_widgets` and `ws_checked`. All common
native files and initial boot/EFI media match byte-for-byte within each
pair. Full staged host module files are checked; no paired FAT or guest
memory readback is claimed.

Fixed source revision: `baced0adb` (`Android: honor styled CompoundButton
indicators`). Both compound262 runs use the actual signed APK
`fef3843e4b78f9e4ae32f93e299fdc342549b378ab8c01af8fabf4314046d029`,
with identical successful signer verification. Fixed262 uses framework
`a37ffeceffd29e7bd5db825e079949f5a6e3f71dd04edba8c61239bd1971b71c`
and native
`3bbc2d9439961be351f18e391f305ded393d7a10b67f1cf2e80adad2a6569b80`.

The final auditor source is
`4a4eb01d2956b6f5a018b73b2604f694d1a0e0c073ba5b569d6d91306fafb799`,
binary `f0d95cf7ec5db23910a4b97782f85844c76f6bd7c5aab36e4753cd2364d1fec8`.
Its actual compilation receipt and compiler are frozen inside `audit/`
before sealing. Earlier failed bundles keep their original auditors.
Strict semantic sealing, the pinned full recheck, authentic
partial-bundle/wrong-pin rejection, and the final `-prod` refusal passed.
Historical compound247 checker/evidence remain unchanged.

Recheck the complete passing bundle with its retained executable:

```sh
/Users/alex/.local/state/vinix/android/compound262-2026-10-24/audit/compound-styled-evidence check \
  /Users/alex/.local/state/vinix/android/compound262-2026-10-24 \
  266c69ebfe021eae6224cfefe920d39ec348a2d1b9c89bc310bc0c60cd837526
```
