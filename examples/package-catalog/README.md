# Native SDK application catalog

Build Hello, Counter and Memo for AArch64 and x86_64 in one private publisher
workspace. Hello reads explicitly supplied text documents. Counter retains a
private count using native window protocol 1; Memo edits/saves a private UTF-8
line using protocol 2. Their existing permissions and MIME registrations are
preserved. Each package includes the SDK, V and musl notices.

With a reviewed V compiler and both target musl GCC compilers on `PATH`:

```sh
V=/path/to/v /path/to/v -path '@vlib|@vmodules|.' \
  run examples/package-catalog/build.v 1.0.0 /tmp/new-native-build
```

The parent directory must exist. `VINIX_MUSL_COPYRIGHT` selects the matching
toolchain's musl notice. The builder creates `roots`, `lock/catalog.json`,
`workspace` and `build.json`. The receipt hashes the prepared files and compiler
executables. It requires a new output, removes its partial build on failure and
uses the profile's atomic lock/workspace publication. Wait for successful
completion before reviewing or signing the workspace.

Review the catalog's six manifests, payload pins, permissions and notices, then
use [`publish-release`](../../tools/packages/SDK.md#build-and-publish) to sign
`workspace`. Authenticate/enroll the publisher key separately; refresh and install
`org.vinix.package-hello`, `org.vinix.counter` and `org.vinix.memo` through Software
or the CLI. No host image rebuild or shared runtime is needed for these static
applications. Select an ordinary `launch_user` for a root desktop session.

For a release image, save the advertised set as a reviewed requirements file
(use `x86_64` for that target):

```json
{"format":1,"architecture":"aarch64","packages":["org.vinix.package-hello","org.vinix.counter","org.vinix.memo"]}
```

Select it with `VINIX_PACKAGE_IMAGE_APPLICATIONS=/absolute/native-apps.json`
alongside the reviewed `VINIX_PACKAGE_IMAGE_CONFIG` and signed offline
`VINIX_PACKAGE_IMAGE_REPOSITORIES` bundle. Desktop staging checks their joint
installability before package-tool compilation, and its cache tracks the selected
requirements and contents. Direct `stage.v --check --applications FILE` returns
the requirements digest and exact deployment lock without changing the image.
See [the release contract](../../tools/packages/SDK.md#application-requirements-files-in-desktop-builds).

Add `--export-deployment /release/new-native-deployment.json` to that check to
save its exact lock directly. The new output must be outside the image. Ship it
with the authenticated bundle, then open its path in Software's **Deployment**
form to review the complete set before applying it. Current publisher trust and
policy are checked again. See [deployment export](../../tools/packages/SDK.md#export-an-image-application-deployment).

Normal image staging with that requirements file also saves the exact lock in
the image. After boot, **Software → Deployment → Review release apps** reviews
Hello, Counter and Memo together from the bundled signed repository. Confirm the
complete plan before administrator approval. The release declaration does not
install apps or change personal data during image construction. See
[image declaration](../../tools/packages/SDK.md#declare-release-applications-in-an-image).

The version argument labels the three application manifests. Publishers must
review source and toolchain changes when advancing it. Binary reproducibility
across different compiler installations is not implied. Signed updates,
rollback, uninstall and cache reinstall use the existing service; private data
survives uninstall unless explicitly purged.

The [native profile](../../tools/packages/SDK.md#native-sdk-publisher-profile)
also accepts independently prepared roots and composes with the Linux catalog
profiles. [Qualification](../../tests/packages/native-catalog-check.md) records
the boundaries exercised. These examples do not complete public publisher
enrollment, migration of the Alpine catalog or full graphical login acceptance.
