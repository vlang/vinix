# Maps account guest controller

The controller provisions separate Maps and Google Play Services principals,
starts the real GMS authenticator broker, and launches the real Maps APK through
the desktop compositor. Broker readiness establishes a service transport only;
this build report does not establish successful Google authentication.

Controller and builder sources were committed in `9fa5e4ad9`, `7a6e71dd3` and
`27d5bfe47`.
The retained build records the complete source revision and hashes of the exact
builder, controller, compiler, imported V sources, native includes, cross tools,
startup files and static link inputs. Host self-tests check canonical paths,
process credentials, registry/APK/service bindings, identity collisions and stale
stop requests. SQLite tests reject changed paths, ownership, modes, link counts,
inodes, sizes and digests, then exercise exclusive file creation, bounded copying
and atomic replacement of a real host hardlink while preserving its alias.
Builder self-tests check dependency/source membership, native helper objects and
static ELF validation.

Final build: `2026-10-26 16:05:28 UTC`, source revision
`d72f0ddcff3288bbec3aeb4191ddc1c63a9ba6f7`. Both retained host self-tests and
the strict AArch64 compile/static link passed. The builder validated complete
source/header/link membership and rechecked original and frozen input hashes
after linking. No QEMU boot was performed for this build.

Complete retained bundle:
`/Users/alex/.local/state/vinix/android/maps-account-guest-build-2026-10-26-r3`.
Its `sha256.json` digest is
`74b972255e2a151a14eb05302f28081de2a091280109f2c0ffded2962e6ad622`;
`bin/maps-account-guest` is
`31e76e6100a83f6d476e892f7571868fc01cc0d7992c6f618b3aba8a32a8ff8b`.
Retain the entire bundle to audit its compiler and dependency closure. The
earlier r1 and r2 bundles are superseded and must not be staged.

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
