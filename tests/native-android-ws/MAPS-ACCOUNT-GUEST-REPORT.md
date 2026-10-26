# Maps account guest controller

The controller provisions separate Maps and Google Play Services principals,
starts the real GMS authenticator broker, and launches the real Maps APK through
the desktop compositor. Broker readiness establishes a service transport only;
this build report does not establish successful Google authentication.

Controller and builder sources were committed in `9fa5e4ad9` and `7a6e71dd3`.
The retained build records the complete source revision and hashes of the exact
builder, controller, compiler, imported V sources, native includes, cross tools,
startup files and static link inputs. Host self-tests check canonical paths,
process credentials, registry/APK/service bindings, identity collisions and stale
stop requests; builder self-tests check dependency/source membership, native
helper objects and static ELF validation.

Final build: `2026-10-26 15:47:12 UTC`, source revision
`db22f699e3aa075d34e239f633b3b3e05a55b4a0`. Both retained host self-tests and
the strict AArch64 compile/static link passed. The builder validated complete
source/header/link membership and rechecked original and frozen input hashes
after linking. No QEMU boot was performed for this build.

Complete retained bundle:
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r2`.
Its `sha256.json` digest is
`a42463cc9a9e98c378e3a313ded8fe7eed092f35e7693472591343f8a9734a86`;
`bin/maps-account-guest` is
`32558ceb85bf316bc896469eedbc6300999da33d276457be1f294417fd55467f`.
Retain the entire bundle to audit its compiler and dependency closure. The
earlier r1 bundle predates stop/cleanup fixes and must not be staged.

The deployment receipt must pin the controller, identical desktop launch slot,
real APKs, identity registry, runtime account/JNI/framework outputs, and both
browser manifests and their dependency closure. Before changing any file mode,
the root controller preflights every selected regular file and its protected
ancestors, ownership, link count and digest, including the deployment receipt.
It then removes write bits, verifies the resulting immutable inputs, and records
the mode changes. Maps uses UID/GID 10012; GMS uses 10013. Existing identities,
processes or private directories using either principal are rejected.
The mutable Unix identity databases remain outside the immutable deployment
input set; provisioning retains their exact before/after bytes and verifies
both preflights before either append.

Run `/opt/vinix-maps-account/bin/maps-account-guest --broker` as root in the
actual desktop GUI terminal. The controller authenticates the compositor
ancestor and window socket peer, preserving credential-free identity evidence.
After `MAPS-ACCOUNT-READY`, open the desktop Android icon and use Maps' account
menu. The same controller is installed in the compositor's launch slot so Maps
retains its native surface and input pipe.

After collecting a screenshot, run
`/opt/vinix-maps-account/bin/maps-account-guest --stop` in a second root GUI
terminal. The request binds to the live controller and broker start identities.
Cleanup uses a Maps process receipt published before its UID drop, adopts
orphaned helpers, kills selected descendants, and reaps using bounded polling.
Surviving processes fail the run. The 15 minute session deadline remains a
fallback.

The controller exports `VINIX-MAPS-ACCOUNT-RESULTS-1` serial frames containing
receipts, identity and input-hardening evidence, and raw-log hashes. Native Maps
and broker logs remain root-private in the guest and are excluded from the
serial archive. No account credentials are supplied by this fixture.
