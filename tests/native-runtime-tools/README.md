# Native runtime host tools

The maintained Debian resolver, dhewm3 builder and guest runner, Dota Mesa/Venus
builders, Vulkan stager and guest runner, QEMU frontend, compatibility generator,
and Vulkan staging fixtures have native V entry points. Their public shell
launchers compile V through `build-support/run-v-tool.sh`; they do not import or
launch first-party Python bridges.

`runtimehost` owns Debian index resolution, six joined download workers, lazy ar
selection and native compressed tar extraction; dhewm3's installer extraction,
native newc initramfs and benchmark/artifact processing; the driver recipes and
compiled LLVM configuration helper; and both guest PTY owners. Vulkan staging
reuses the existing V policy through a synchronous typed adapter. Private
temporary directories retire on errors as well as success. Process groups keep
their PID reserved until the owner closes and reaps them.

Run the offline staging regressions with `tests/dota2/vulkan-stage-test`. For the
other fixtures, compile `test-debian.v`, `test-doom.v`, `test-build.v`, or
`test-session.v` and pass a new work directory. The staging suite retains all 18
original named cases. The session suite runs 17 whole mock PTY sessions with
large serial output, artifacts and reports, failures, deadlines, SIGINT and
SIGTERM, then checks that each child is gone. Build fixtures inspect the real
native command recipes while substituting upstream build effects.

The native package-marker serializer retains ASCII JSON escaping, key ordering,
WTF-8 and filesystem surrogateescape bytes. Darwin rejects invalid UTF-8
filenames, so their serialized representation is checked independently of the
real `.deb` extraction and cache fixtures.

Mesa's upstream generators still require an existing Meson/Mako installation;
`VINIX_DOTA2_MESON`, PATH or an existing `host-venv/bin/meson` selects it. Upstream
QEMU still needs its configure interpreter and dependencies, selected through
`VINIX_DOTA2_QEMU_PYTHON` when necessary. The first-party drivers do not create a
Python environment or run pip. No interpreter or Meson execution is used by the
offline qualification, and it does not claim a fresh upstream game/driver build
or real Vinix guest boot.

Machine-local frozen source and qualification receipts are retained under
`~/.cache/vinix-runtime-tools-native-20261012/`.
