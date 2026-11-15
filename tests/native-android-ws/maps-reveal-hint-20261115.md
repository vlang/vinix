# Reveal-on-focus hint, 2026-11-15

The ValueCallback interface in 6a301fe1c passed the complete signed ARM API
suite in r103 and again in the full r104 profile. Staging r104 passed after
space recovered, but QEMU46363 was terminated by signal 15 from an external
process before services became ready. Some terminal input was dropped. Its
complete signed API export is retained, plus partial persistent API evidence;
there is no account export or successful account-attempt claim for r104.
PID absence and no open image handles preceded read-only extraction, and
read-only e2fsck passed. The interrupted guest was not relaunched.

A fresh r105 used the same qualified artifacts, checked its persistent volume
before starting the broker, and used slower terminal input with observed
prompts. The existing r103/r104 signed qualification was reused. GMS PID23853
reached readiness; its descriptor snapshot captured 240 entries, unavailable=0,
non_atomic=true. Maps PID35831 opened the chooser and attempted Add account
once. The callback-type failure was gone; account RichTextView.setText failed
on the missing inherited View.setRevealOnFocusHint(Z)V method.

The V SDK adapter adds the public final setter and getter. An opt-out field
defaults every constructor to true without allocating or modifying constructor
chains. Setting the preference does not request focus or scrolling. This
matches the [Android hint contract](https://developer.android.com/reference/android/view/View#setRevealOnFocusHint(boolean))
and the [AOSP inverse-flag implementation](https://android.googlesource.com/platform/frameworks/base/+/HEAD/core/java/android/view/View.java).
Vinix's current native focus path does not automatically reveal a focused view;
the new API retains a queryable preference for ancestors without adding that
separate behavior. Existing explicit rectangle requests are unchanged.

The signed regression covers View constructor variants, TextView inheritance,
the default, repeated false/true writes, per-instance independence, persistence
across setText, unchanged focusability and no focus acquisition from the hint.
The SDK builder rejects six missing/duplicate baseline declarations and three
already-present members before full assembly and View DEX readback.

## Retained full-profile evidence

External root: /Users/alex/.local/state/vinix/android.
The r104 full-profile signed suite passed, child exit 0; complete API export:
23727 bytes / 47 chunks, reconstructed without removals.

| r104 API evidence | SHA256 |
| --- | --- |
| maps-value-full-api-uart-20261115-r1/full.log | bf584e24b2e20efb578b77b4d39c5c392f927d362a0044fb003a21000586ce89 |
| maps-value-full-api-readback-20261115-r1/archive.json | 52880234bfacf960cb03788b8297d4cf65470a82ce19fdc41e1b7cc3e5721fb9 |
| maps-value-full-api-child-20261115-r1/child.log | 61ed6e51e82dbfdac71635f1e8ab8e52d7f6394bf606ffb0ccf46b02cbfd2455 |

In r105 the checked volume UUID was a10c5d6495354544979c14820cc6507b. After the
failure's complete export ended, full account results were copied to
r105-private/results and synced; mount check, copied receipt and prompt were
observed before stopping owned QEMU65274. PID absence and no image handles
preceded read-only extraction. e2fsck passed; the storage watch is partial.
No credentials were entered and the protected session was not restarted.

The private root is maps-current-20261115-r105-account/private-readback.
Logs match their private manifest. The complete Maps export reconstructed
without removals: 1429082 bytes / 2792 chunks; its receipt compares identical
to the private copy.

| r105 account evidence | SHA256 |
| --- | --- |
| maps-r105-uart-20261115-r1/full.log | 5c0eaf551ac98dfb58930840549fd01b498d20620b68131fac6363c7751faaef |
| maps-r105-readback-20261115-r1/archive.json | 7b856552aa434ec8e3817e6a2f088a52dd09b1346a325a4f4790570b12f48820 |
| Same readback/exported-receipt.json | a6495e0559241a27e379ca11fa17c23affcf1e004015614c4b6d3efa6d05a548 |
| Private r105-private/results/broker.log | 865452d45d2b86838c2420fec3561d6cdf1cdb790c278560110eab43c11ca3e5 |

## Candidate build checks

Current V: /Users/alex/code/v/v, V 0.5.2 cbfc1be. Original build caps remain
RSS 629145600, wall 300000 ms, reserve 1073741824, growth 536870912 and output
4194304 bytes. Generated C, inventories, binaries and raw results stay outside Git.

SDK assembly/readback and nine input refusals passed in
framework-reveal-hint-20261115-r1: 3088 ms, peak sampled RSS 496189440,
observed growth 29921280 bytes. Signed fixture assembly/signature verification
passed in current-api-reveal-hint-20261115-r1: 2928 ms, RSS 173359104,
growth 8523776 bytes. Both guards returned exit/child 0/0 and complete cleanup.

| Candidate artifact | SHA256 |
| --- | --- |
| framework-reveal-hint-20261115-r1/classes.dex | 83deabba85785cb967a4e297786ddfb8b8123f89fdc5e702aa9cc6f51c4bc4f3 |
| current-api-reveal-hint-20261115-r1/probe.apk | b6f26767ad029436f1411e9a0fe14b5720e38dfe96a30d8d5540c4121e6a7ca2 |

Native attempt reveal-hint-native-20261115-r1 was stopped after 18640 ms for
observed shared disk growth of 542175232 bytes. Peak sampled RSS was 531365888;
exit/child 125/137, cleanup complete. The original caps are unchanged. Native
qualification was retried as recorded below. Signed ARM execution and the next
real account attempt remain pending. Google Maps is not fully qualified and no
Google authentication success is claimed.

With all owned guests stopped, reveal-hint-host-quiet-20261115-r1 also hit its
stricter read-only growth allowance: 132468736 bytes observed in 10357 ms,
growth cap 67108864, exit/child 125/137, cleanup complete. A fresh full native
attempt r2 uses the original larger build allowance without relaxing any cap.

The full native retry reveal-hint-native-20261115-r2 passed under the original
caps, including the AArch64 GCC -Werror link: elapsed 130129 ms, peak sampled
RSS 586661888, maximum observed shared growth 337125376 bytes, exit/child 0/0,
empty reason and complete cleanup. The library SHA256 is
0c3ecc38eb45c551a7712cdc00a6e8f533307da6ef3645500a86e46e6cfe5a02
at reveal-hint-native-20261115-r2/native/libvinix-android-native.so.

The attempted r106 API-only profile explicitly omitted the account data disk.
Guard maps-r106-stage-20261115-r1 refused even that staging before launch:
initial free 1540935680 bytes, reason "disk growth budget", exit 125,
child -1, pid 0 and no supervised groups. cleanup_complete=false accompanies
the prelaunch refusal; no command or r106 guest started. No build cap was
relaxed to fit the shrinking free space.

The SDK and signed fixture above and this successful native retry are ready
for fresh signed ARM qualification. They do not yet establish ARM success or
successful account-screen rendering. All owned guests are stopped. Resume by
staging these exact qualified host artifacts in a fresh guest after restoring
space and a quiet disk window, then run the signed suite before a protected
account attempt. Source/compiler requirements remain current V, without a
historical compiler pin.

## r107 signed ARM qualification

After space recovered, the retained SDK/native/fixture artifacts matched their
recorded checksums and fresh full-profile staging passed under the original
caps. The complete signed ARM suite passed with child exit 0. Its log contains
REVEAL-HINT-PASS and CURRENT-API-PASS, including constructor defaults, inherited
TextView methods, repeated toggles, independent state and no focus acquisition.
The complete API export reconstructed without removals: 23863 bytes / 47 chunks.

| ARM API evidence | SHA256 |
| --- | --- |
| maps-reveal-api-uart-20261115-r1/full.log | bb63dfb6db754e913fdd672df75640bf20ad3da87065be42653215de4b2bc54c |
| maps-reveal-api-readback-20261115-r1/archive.json | 707746a751f57d6241a8f2374f1df84998ba86e0e073e8118e06df861009e535 |
| maps-reveal-api-child-20261115-r1/child.log | dd94939d591e0232dd40a9caaf2051c1506d6f525d80377dd240fbf1d3aaccdd |

The real protected account retry is pending in r107. No full Maps or Google
authentication claim follows from the API qualification.
