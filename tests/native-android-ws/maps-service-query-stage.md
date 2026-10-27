# Maps explicit service-query diagnostic overlay

`maps-service-query-stage.v` appends a framework-only diagnostic overlay to the
sealed `maps-controller-r1` image. It has its own receipt kind,
`vinix-maps-service-query-diagnostic-v1`. The pinned successor framework changes
one existing `PackageManager.queryIntentServices(Intent,int)` implementation;
it adds no classes, methods or fields. Its complete producer retains both DEX
inventories and the original protected-storage framework identity.

The six regular payload files are the framework JAR and DEX, the headless
`framework-build.json`, `framework-sha256.json` and `guest-inputs.json`, and the
Maps deployment `build.json`. Headless input pins change only the existing
framework JAR key. The Maps receipt changes exactly five existing input pins
for those framework and headless files, plus its `framework_manifest_sha256`.
All other decoded values and key sets must remain equal. The JNI, both
controller aliases, launcher, APKs, accounts, browser and sandbox roles retain
their complete original bundles and identities.

The stager checks the exact complete controller base, all sixteen inherited
manifest bundles and the new framework bundle before and after staging. It
audits destination and ancestor inodes in original module order, preserving
first-inode modes, APFS-clones only boot media and firmware variables, and
appends `maps-service-query-diagnostic.tar`. Independent FAT readback checks
the overlay, Limine configuration and all nine unchanged modules. No SDK or
runtime tree is copied or rebuilt. TAR and large-file hashing use bounded
buffers; the host stager uses Boehm GC.

Build and prepare with one compiler at a time:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-service-query-stage \
  tests/native-android-ws/maps-service-query-stage.v
/absolute/external/maps-service-query-stage --self-test
/absolute/external/maps-service-query-stage --prepare /absolute/external/fresh-output
```

This separate diagnostic stage records the intentional framework successor
while preserving the original native producer's protected-framework coupling.
It does not alter production staging compatibility rules or authentication
checks. It is a credential-free framework isolation input, with no Google login
claim. The retained source and executable closure is not hermetic: host V/C
toolchains, libraries, SDK and operating system remain environmental inputs.
Preparation preserves the original kernel; use the separate service-query
kernel-patcher profile on a fresh mutable clone to install the frozen pidfd
kernel before booting. Prior producers and patcher profiles remain unchanged.
