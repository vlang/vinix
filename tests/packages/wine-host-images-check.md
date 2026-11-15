# Observed compiler/linker host images and child environment

Managed Homebrew Clang/LLD children now use a closed environment with fixed
PATH, locale, timezone and source epoch, private HOME/TMPDIR directories, and
`DYLD_PRINT_LIBRARIES=1`. Parent include/library search variables, credentials
and loader injection settings are not inherited. V compilation, controller
builds and other host tools remain outside this environment contract.

Before the first managed command in a build, both pinned tools run `--version`
under that environment. Their observed image identities are merged and the
canonical ordinary non-system image files are hashed. Every managed resource
query, C discovery/compile, linker version query and link replay records its
actual environment and dyld observations. Selected image UUIDs and bytes must
match the before-command probes; unrecorded non-system images refuse.

The parser checks PID/UUID/path syntax, rejects conflicting identities, and
deduplicates repeated image paths across child PIDs. Known dyld “move loaded to
delayed” notices are accepted only after that PID reported the named image.
Unknown diagnostics refuse. Raw dyld logs remain separate from compiler/linker
output, preserving existing C include and linker-version admission semantics.

Paths in `/usr/lib/` and `/System/Library/` are explicitly **metadata-only**.
Their recorded UUIDs are retained; no file hash is invented for shared-cache
images that have no ordinary file. This does not admit macOS shared-cache or
loader bytes, and the selected host image scope is not a complete dynamic or
hermetic toolchain qualification. Other non-system images must be canonical
ordinary files and pass the full byte checks.

Final producer/controller checks, native before/after-boot checks, independent
producer admission and full retention require these records in addition to all
existing source, C, header, linker-replay, runtime, PE and ISO checks. Namespace
and exact environment checks preserve the original recorded build locations in
copied graphs. Ordinary image records stay ordinary in copies. Non-system image
paths join retained artifact maps; newly loaded non-system image bytes cannot
be silently omitted by resealing an output map.

`wine-host-images-snapshot BRIDGE_LOGS GUEST_LOGS PACKAGE_LOGS FRESH_OUTPUT`
admits all three contexts, deduplicates selected ordinary image bytes into a
content-addressed store, preserves modes and rechecks inputs/records afterward.
OS shared-cache bytes remain excluded. Build it with `-prod` and the repository
on V's module path.

Module controls check malformed traces, PID/UUID errors, unknown delayed-image
notices, missing images and the explicit OS byte boundary. The real macOS child
control poisons the parent's `DYLD_INSERT_LIBRARIES`, requires the controlled
child to succeed without inheriting it, then requires an added CPATH entry in
its recorded environment to refuse. Optional `VINIX_HOST_IMAGE_TEST_STATE`
preserves raw test state in a fresh external directory.

The full retention runner requires thirty-nine resealed refusals after real
and unchanged copied baselines pass. Five new cases omit a before-command
image, alter a child environment, omit an observed image, change a recorded
image hash or link an image receipt. Every case must fail at its named check
without retained output, using private copies and detached mutation writes.

Remaining gates include OS shared-cache/loader bytes, V/host-controller and
other host-tool coverage, unreported inputs/search absence, full hermetic
admission, default activation, owned ARM/GUI and broader roadmap 14 acceptance.
Historical complete bundles and original verifiers remain required. This
feature changes qualification tooling and does not activate a product default.

The x86 checkpoint is `/Users/alex/.cache/vwhostimages-20261115-01`, from
isolated base `44d4689f7`. Production/manual-free parser and real child controls
pass, including exclusion of the parent's invalid loader-injection setting and
refusal of an altered recorded environment. The initial delayed-image trace
refusal remains preserved; only notices tied to prior same-PID observations
were added to the accepted grammar. A real linker probe, fresh PE/runtime and
independent producer admission pass. `native-01` passes signed holder-death and
collection in 93.933 seconds with post-run image verification. All 32
owned-receipt controls pass. Observed C byte/mode snapshots, selected ordinary
host-image byte/mode storage and the selected resource-header copy are retained.
Original selected prerequisite bundles and historical verifiers remain required.
Real and unchanged copied retention baselines pass; all thirty-nine resealed
mutations refuse at their named gates without retained output, including all
five new host-image and environment cases.
