# Native validation tools

The maintained host entry points are `examples/ios-ppsspp/download`,
`download-cube`, `download-gow`, `download-nzp`, `build-support/steam/qemu-dns`,
`tests/roblox/launcher-test`, `desktop/tools/test-gpu-present`,
`tests/codex/smoke`, `tests/claude/smoke`, and `tests/packages/x-window-check`.
Each selects the repository's V compiler through `build-support/run-v-tool.sh`.

The PSP fetchers preserve the upstream package pins, checksums, binary identity
checks and extraction limits. They validate the whole ZIP directory before
writing, reject traversal, special files and destination symlinks, and publish
verified downloads by rename. An invalid existing package remains intact on a
failed replacement. The cube fetcher repairs invalid cached copies.

`guestvalidation` contains the guest commands without the host package or build
dependencies. `build-support/build-validation-guest --arch aarch64|x86_64
--output PATH [--sysroot DIR --static]` cross-compiles this module against the
Alpine musl development sysroot. The result selects its command from the installed
basename (`qemu-dns`, `x-window-check`, `codex-smoke`, or `claude-smoke`).
`validation-guest COMMAND ...` also accepts an explicit command. X11 requires
the dynamic musl build to load the installed `libX11.so.6`; the smoke and DNS
commands can use the static build. The source, selected V compiler and vlib,
compiler version, sysroot headers, startup objects and runtimes participate in
the checked executable cache. Corrupt cached executables are rebuilt.

The DNS command keeps the original query, resolver order and 15 retries, and
only replaces QEMU's proxy after an external resolver answers and the proxy
fails. The CLI smoke commands serve the original event-stream responses on a
private loopback port. A server thread handles HTTP while the process SDK alone
owns, terminates and reaps the client process group. Threads are joined before
their listener, state or private client home is released.

The X11 checker uses explicit C-width fields and callbacks, legacy or UTF-8
titles, the original viewability and recursion rules, and releases every native
title, property, child list and display. Its fixture counts native owners across
successful, absent and repeated checks. The GPU command compares all 67 cases
with the immutable original C presenter, including both complete output streams,
pixels, stack lifetimes and sanitizer checks. It writes its frozen reference and
artifacts outside the repository.

The native fixture programs are `test-download.v`, `test-dns.v`, `test-smoke.v`,
`test-streams.v` and `test-xwindow.v`. Compile the X11 fixture from
`xfixture/main.v` with `-shared -path '@vlib|ABSOLUTE_PATH_TO_THIS_DIRECTORY'`,
then pass its library path and an artifact directory to `test-xwindow`.
Other fixture programs take an artifact directory. CLI smoke fixtures execute
native mock clients and compare inert historical response literals from Git;
they do not run Python or contact an external model service.

`test-smoke-signals.v` takes host and guest frontend executables, the compiled
`test-smoke` mock program, and an artifact directory. It checks SIGINT/SIGTERM
status, thread joining, client retirement and descriptor cleanup for both CLI
families. `test-guest-build.v BUILDER ARTIFACT_DIRECTORY` checks both ELF
architectures with static and dynamic musl, warm and corrupted caches, and
preservation of an existing executable when linking fails. It pins the selected
compiler executable so another session's compiler rebuild cannot change the
cache key halfway through the test.
