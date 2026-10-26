# Maps account guest controller

The controller provisions separate Maps and Google Play Services principals,
starts the real GMS authenticator broker, and launches the real Maps APK through
the desktop compositor. Broker readiness establishes a service transport only;
this build report does not establish successful Google authentication.

Controller and builder sources were committed in `9fa5e4ad9`, `7a6e71dd3` and
`27d5bfe47`; `e9273eb11` fixes the broker's runtime directory.
The retained build records the complete source revision and hashes of the exact
builder, controller, compiler, imported V sources, native includes, cross tools,
startup files and static link inputs. Host self-tests check canonical paths,
process credentials, registry/APK/service bindings, identity collisions and stale
stop requests. SQLite tests reject changed paths, ownership, modes, link counts,
inodes, sizes and digests, then exercise exclusive file creation, bounded copying
and atomic replacement of a real host hardlink while preserving its alias.
Builder self-tests check dependency/source membership, native helper objects and
static ELF validation.

Final build: `2026-10-26 16:57:27 UTC`, source revision
`e9273eb114115a9856d693891c7f53cdb257a0d3`. Both retained host self-tests and
the strict AArch64 compile/static link passed. The builder validated complete
source/header/link membership and rechecked original and frozen input hashes
after linking. No QEMU boot was performed for this build.

Complete retained bundle:
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r4`.
Its `sha256.json` digest is
`e1cb7b91510e184852a6ea7960eb5540804b1f826e17ce2e4991620eff6e083b`;
`bin/maps-account-guest` is
`28a7f5a83d5d1cd72b2c56532065f1599db1f972359932899206528b23f511f4`.
Retain the entire bundle to audit its compiler and dependency closure. The
earlier r1, r2 and r3 bundles are superseded and must not be staged.

The broker uses canonical `/run/vinix-maps-account`, avoiding the guest's
`/var/run` alias. Protected-directory checks reject symlinks and unsafe modes;
the retained host self-test covers both rejection cases. This fixes the path
admission error observed in the previous guest run. The r4 cross-build does not
establish that the guest broker or Google login succeeds.

The baseline SQLite library has one audited versioned hardlink. Before immutable
input admission, the controller requires exactly the two fixed root-owned
`0755` paths, their shared inode and link count two, and the known SQLite digest.
It copies the canonical library to an exclusively created fresh inode, rechecks
the original group, and atomically replaces the canonical path. Both resulting
files must have link count one, unchanged bytes, and the preserved versioned
alias must retain its original inode and metadata. The private
`sqlite-dealias.json` receipt records the before/after identities. All other
inputs retain strict single-link admission.

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

The r5 controller adds public numeric authenticator initialization diagnostics
in `receipt.auth_init`. Commit `19bb95f17` accepts only complete, exact LF records
with canonical signed 32-bit values and the native producer's stage, detail and
loader bounds. It retains at most 32 records and marks overflow explicitly.
Malformed, partial and private log fields are excluded. Capture occurs on both
success and failure without changing readiness, deadlines or cleanup. Pure host
self-tests cover integer limits, malformed records, field bounds, privacy,
partial lines and cardinality; independent source review passed.

The fully retained r5 build completed `2026-10-26 19:03:15 UTC`, recording source
revision `ecbd3964aff243304e16df45271c7de8dee4d2da`. Its exact compiled controller
source is `312e6a02d7c4ec51a3615ac100f1e8f045c06fda6d39dadfb5f750c1f9f99c47`.
Both retained host self-tests, source/header/link membership checks and strict
static AArch64 compilation passed. The unchanged builder and native baseline
retain their complete original and frozen input closures. A separate production
stager audit rehashed all 3,100 regular files successfully; its log is
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-r5-inventory-audit.log`
with SHA-256 `384fcf951b0f776ac90b782cea79a65ff1f2c78b789bd3873c6e2754fbaa9447`.

Select the complete r5 bundle at
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r5`,
whose `sha256.json` digest is
`1841922e5196125b5a6198635fd28fe0d87d49e530bec9db903b3fe44d7cac92`.
Its sole ARM output, `bin/maps-account-guest`, is
`72fdd227adc3244329b673ea9ca46b3ecffd4e3d1d7725368475d6d5e4048cb2`.
This supersedes r4 for subsequent staging; historical bundles remain intact.
No guest boot or Google account login is established by this build.
