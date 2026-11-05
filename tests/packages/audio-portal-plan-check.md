# Native audio preparation plan checkpoint

`audio-portal-prepare-plan.v` encodes the maintained preparation runner's exact
typed Plan. It accepts a checksum-pinned canonical empty template and an
optional checksum-pinned canonical inspection map, checks all root/file roles,
and exclusively creates a mode-0600 output. Existing files and symlinks refuse;
failed partial output is retained. It formats reviewed stopped inputs and does
not perform semantic admission, target compilation or guest execution.

The strict production host build passed with pinned V
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
LLVM 23 clang, `-prod -nocache -keepc -backend c`, and
`-Werror=incompatible-pointer-types`. Source SHA-256 is
`08dd6dd8b158c94ab7b3e0c2b8921b6b65a9ee3199ad9cc4f1ee23b13ad7f003`;
binary SHA-256 is
`970f7d687f142d0fb9251ea96a703620d2619c96859c9ae7a8ce97673d97d925`.
Independent source review passed. Six direct controls passed: the initial
canonical roundtrip; existing-output, wrong-digest, missing-role-map and
symlink-output refusals; and final encoding of the real large inspection map.
Refusals preserved existing bytes and metadata and created no rejected target.

The fresh independent sparse source is committed as
`56941c3e3d059911b736f4ac21d169f122013b5d`: baseline
`069036c7d8468720dc83f8703d4e797757733a2d` plus the five qualified changes from
`a443190dc20e8e9736874176055dd5221aa77ac0`. All ten audio implementation pins
match that qualified profile; complete base-exclusion comparison passed.
The source includes the baseline plist module used by package CLI imports.
Selected files have independent inodes and nlink 1; Git status is empty.
Source metadata was sealed once, with manifest SHA-256
`503458465bb98be7c88a18a177a43e58062bd9f3018b7c1c70e51e2868d03afc`.

The already-qualified runner, controller and host-build receipt were copied
independently from the [151-control host run](audio-independent-fixtures-check.md),
with unchanged original metadata, exact bytes and modes, nlink 1 and distinct
inodes. This reuses those host builds; it does not repeat the 151 controls.

The maintained `--inspect` returned actual exit 0 and its exact marker. Its
complete 43-role input map is 14,984,288 bytes, SHA-256
`f8042cffc824c38a0ae92c99167e965d8ee070844a4a157222956062378c11be`.
The new canonical final Plan is 14,988,645 bytes, SHA-256
`d939f4091b42d556db5739845e9f099c0f2cd877a0be4332b91beeb665e90290`.
The absolute musl loader link retains its literal unresolved host identity;
the complete sysroot map separately covers libc, and the unchanged controller
uses its confined guest-path resolver before actual target compilation.

Original complete checks for the new source, frozen host source, compiler,
selected kernel and original full kernel bundle passed before compilation,
after compilation and after inspection. All 14 authority anchor digests stayed
equal. Private module directories and the new content store remain empty.
Final six-root endpoint observations were 496,604 KiB allocated and 670,134 KiB
apparent under the unchanged 2 GiB cap, with 70,360,576 KiB actual free. Direct
commands had the retained timeouts; observed logs remained below 16 MiB and
Plan/map files below 32 MiB. These are endpoint observations without continuous
resource, RSS or unconditional descendant-cleanup claims.

The complete setup and inspection evidence is retained outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-independent-fixtures-aarch64-prepare-20261104-01`.
Literal command arrays, cleared environment, raw logs, original metadata
checks, generated C and all plans remain there. `setup/inspection-result-01.json`
SHA-256 is
`dc1fbe029a956bfb094f0cbafe2c9e2d4309bfc36250d0919bafa45e980f28a1`;
`setup/commands-complete-01.json` SHA-256 is
`fd54ad76e348baadc759f5f6614b177ffbce49adb68f9e3db9b23dc1c63a7130`.
This checkpoint has no whole-setup bundle audit, target build or native audio
acceptance claim. Target preparation still requires a separate measured
projection that counts both content-store and captured-input hardlink paths,
generated outputs and receipts within the existing cap. Historical failed
bundles and their independent source snapshots remain untouched.
