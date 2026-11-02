# Messenger Binder delivery and retained native

The API-28 GMS network scheduler supplies an IBinder-backed Messenger. The
previous constructor discarded that Binder and installed a no-op sender.
Core `23296f853` and Message provider `2166f55d7` connect Messenger to the
existing Binder/Parcel transport and real Handler queue. The
[source report](../native-android-tools/messenger-source-check.md) records the
bounded caller and API-28 contracts. This adds no cross-process Binder
credential or transport backend.

Messenger now resolves a local IMessenger or Proxy, returns the actual target
Binder, compares/hashes Binder identity and supplies its Parcelable creator and
nullable strong-Binder helpers. Stub validates the interface token, decodes the
Message presence flag, dispatches transaction one, and delegates unknown codes
to Binder. Proxy sends the API-28 one-way transaction with null reply, ignores
the boolean result and recycles its Parcel on success or propagated failure.
Handler's Messenger implementation stamps Binder.getCallingUid before its
existing sendMessage path; serialized sender values do not replace that stamp.

Message preserves queue, pool and copy behavior while adding Parcelable,
CREATOR and sendingUid. Constructor/recycle initialize the UID to -1; both copy
paths copy it. Its wire contains what/arg1/arg2, nullable Parcelable object,
when, Bundle, nullable reply Messenger and UID in that order. Callback rejection
precedes writes; the exact ClassCastException interval produces the API-28
non-Parcelable error. Creator reads the symmetric wire through Message.obtain.

Producer `147d9c296` adds `--messenger-binder` over the exact Usage SDK. Dedicated
independent raw/canonical oracles admit these controlled metadata changes and
the obsolete Messenger$1 replacement; historical generic gates stay intact.
They preserve all unrelated fields/methods/annotations and enforce every new
instruction, register, declaration, branch, catch span and creator bridge.
Both factories validate their merged class set/collisions, and all five pure
transformations complete before any generated class is written. Whole-class
and JAR checks surround complete API-28 DEX assembly: 2,112 classes become 2,115,
with only five existing classes changed and three classes added. Handler,
Binder and Parcel remain completely unchanged. Independent source and complete
artifact reviews approved, including all eight raw/canonical classes, the whole
class-tree delta and streamed JAR DEX.

| Existing class | Replaced methods | Added methods | Removed methods |
| --- | ---: | ---: | ---: |
| Messenger | 4 | 4 | 0 |
| Messenger$1 | 0 | 5 | 2 |
| IMessenger | 0 | 0 | 0 |
| Handler$MessengerImpl | 2 | 0 | 0 |
| Message | 5 | 1 | 0 |

Messenger and Message add their public static final CREATOR fields; Message
also adds public sendingUid. Messenger$1 drops only its obsolete captured
this$0 field and binds its enclosing method to Messenger's class initializer.
IMessenger becomes public and extends IInterface;
Handler$MessengerImpl extends the new Stub. New Stub, Proxy and
VinixMessageCreator classes have exactly four/four/three methods. Explicit
removal maps appear only in this new profile's receipt.

| Admitted operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Fresh producer compile r2 | 1.733 | 395,100,160 | 415,350,784 |
| Complete producer self-tests r2 | 0.357 | 15,466,496 | 14,483,456 |
| Complete SDK production | 46.407 | 511,623,168 | 496,074,752 |
| Complete retained-native admission | 2.641 | 51,363,840 | 64,225,280 |

SDK production passed its first attempt. Producer compile r1 rejected V array
concatenation in a scope test, with guard and child exit 1 and complete cleanup.
Only test array construction changed to append; providers, oracle policy and
limits stayed intact.
The entire failed r1 root remains retained. Fresh r2 compile/self-tests and full
production exit zero with complete cleanup and zero swaps. Production observed
288,645,120 bytes shared growth under unchanged 600 MiB aggregate RSS,
300-second build/test, 1 GiB reserve, 4 MiB output, file cap 16777216 and
512 MiB/1 GiB tool/SDK growth limits.

Paths below use `S=/Users/alex/.local/state/vinix/android`; the complete SDK is
`S/combined-account-webview-messenger-binder-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline Usage SDK manifest | `bfadac214671937539a4732b3ca6be22d561c366b96a72a9de045fc362aba1fe` |
| New SDK manifest | `e3d313ae3e51404da203344ef1a6db32a4aaf24fe01ac971a71fd69ae586aa85` |
| SDK `build.json` | `8804ebf214adfae4f07e0b59d88d4de558e857df674ebbee47eb60988852454e` |
| Framework JAR | `ddeeb613e7767cbfb3e2bf3818ff02f8f9ab10918f26868dba8047a2cc539129` |
| Framework DEX | `72f53fda25f6165c5cde7ff769596153ab14b89ab2bc69f060bc40dc62f5b345` |

All eight raw/canonical class hashes remain in the complete SDK inventory.
The immutable receipt records source revision
`147d9c296be9470284a544eecaf5bc80b7adc7bb`, containing both provider commits.
Current, committed and frozen producer/provider/integration pins match;
builder/provider source closures retain 271/144 entries. Complete controls are
`S/messenger-binder-framework-builder-2026-11-02-r1`, matching `r2`, and
`S/messenger-binder-framework-production-2026-11-02-r1`. Only classes.dex changes
inside the JAR. Complete compiler, helper and smali-tool inputs stay retained;
host SDK and dynamic libraries remain documented environmental dependencies.

Joint sealing and a separate fresh-process readback passed for eleven roots,
7,988 typed entries: complete source proof, caller audit, four fixture/control
roots, four SDK/producer-control roots, and the uncompiled fixture proposal.
The root list is `S/messenger-binder-producers-sealed-2026-11-02-r1/roots.txt`;
its `sealed/manifest.json` hashes to
`8d21336afbaf8861710b6872390da77c5f2ec4ad0a9413b7588056d4e8b089d6`.
Seal/readback took 0.672/0.849 seconds, sampled 28,295,168/24,018,944 bytes RSS
and observed 3,440,640/1,347,584 bytes shared growth. Both guards/children exit
zero with complete cleanup and zero swaps under unchanged 600 MiB RSS,
900-second, 64 MiB growth and 1 GiB reserve limits.

The seal retains source-proof r1's compiler-notice rejection and r2's equivalent
Smali apostrophe-escape rejection alongside successful r3. The final checker
normalizes only that const-string encoding, with a positive equivalence control;
instruction targets and typed catch spans stay exact. The caller audit retains
its failed curl transfer (exit 56) and retry. Fixture r1 compiled but assembly rejected
four long literals lacking their L suffixes; complete r1 and corrected r2
sources/results remain, as does the failed producer compile. None of these
failed attempts is presented as a pass. The sealed proposal was not a build
input; complete integrated fixture sources are retained. The complete parent
Usage SDK and historical prerequisite bundles remain required.

The retained native bundle remains
`S/current-native-build-2026-11-02-broadcast-permission-r1`, manifest
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`,
DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`,
and original broadcast-SDK provenance
`49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5`.
Its original complete bundles remain required at the twelve-root seal
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.

The full SDK/native gate passes the exact 2,112-to-2,115 class delta, explicit
method/field removals and generated-provider preflight ordering. All 70 consumed
classes remain canonically equal. Exactly two raw formatting pairs come from
the canonical clone; the other 68 raw classes stay equal. All eight Messenger
classes are outside generated membership. Whole Handler/Binder/Parcel and
ContextImpl remain unchanged, including the latter's manually referenced native
theme/resource/loaded-app fields and methods. No native rebuild, binding change
or provenance relabel occurs.

| Consumed class | Original raw SHA-256 | Successor raw SHA-256 |
| --- | --- | --- |
| Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |

The gate checks the complete original 91-origin/92-input native source map,
721 exports, generated JNI/C, all 58 consumed C/header inputs and 650/340-entry
builder/generator helper closures. The native bundle remains coupled to its
original broadcast SDK. Actual admission guard/child exits are zero, cleanup
is complete, swaps are zero and observed shared growth is 1,638,400 bytes under
unchanged 600 MiB/900-second/512 MiB growth/1 GiB reserve limits.

Actual admission evidence is
`S/maps-messenger-binder-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`cf4bcd503a6c3a1d24160b6fb1d6b4efcb190633b1b9732b578cf9c7af7f5282`;
the complete log hashes to
`f54c58a84b5b0041fd352ed8beb21a240804298693f4fdedab4492fec563b7e7`.
Current and frozen admission source both hash to
`9626ccb43511dcb92081f2eef0ec245d031a3921e26258d88e7a25587ef1f0b4`.
Complete media-tool qualification is reported separately. ARM, live GMS/Maps
behavior, authentication and imagery remain separate runtime checks.
