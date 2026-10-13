# Native V application packages

Build with `v -o /tmp/vinix-package tools/packages/main.v`. Install/state commands
support a disposable `--root /absolute/root`. Launch uses the real root and an
ordinary identity. The root desktop can hand off to an administrator-configured
`launch_user` through the isolated account session runner.

Both desktop builders use the existing native security-tools staging path.
Standalone staging and qualification are also available:

```sh
v run tools/packages/stage.v --arch aarch64 --staging /path/to/root
v run tools/packages/stage.v --arch x86_64 --staging /path/to/root
v run tests/packages/distribution-check.v --cross --desktop
```

Desktop checks need generated examples under `build/app-src` and a headless ui2
overlay under `build/vmodules`; `VINIX_PACKAGE_TEST_UI2` selects another overlay
parent. Package implementation, publishing, staging and qualification use V.
The driver also accepts `--direct-tests` to compile/run each existing assertion
runner directly when the compiler's cached `vtest` tool cannot run. These runners
retain declarations to avoid pruning required crypto types. The launcher heap
fixture disables the compiler's crash handler in its separately linked C unit;
assertions and process exit failures still fail the check.

Use `publish-release REPOSITORY_DIR ID SEED_FILE SEQUENCE EXPIRES_UNIX NEW_DIRECTORY`
to emit a complete signed consumer repository with atomic publication, dependency
closure validation on each declared architecture and retained publisher sequence
history. The legacy `publish` command remains available for workspace metadata.

Read [administration/recovery](../../docs/application-distribution.md) and
[SDK 1](SDK.md) for enrollment, policy, packaging and limits. Release publisher
enrollment and catalog/runtime guest qualification remain required.

Use `pack-catalog CATALOG.json PREPARED_ROOTS NEW_WORKSPACE` to assemble reviewed
prepared-root recipes and pinned inventories atomically, with complete declared
architecture/version/runtime coverage. It emits a canonical catalog lock and a
private publisher workspace for `publish-release`. See the
[catalog contract](SDK.md#build-a-pinned-application-catalog).

`sqlite-catalog SQLITE_VERSION RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY`
creates the concrete SQLite CLI/musl runtime lock for both supported hosts. It
retains redistribution notices and separates compatible library updates from
the CLI. See the [publisher profile](SDK.md#sqlite-cli-publisher-profile) and
[real SQLite lifecycle qualification](../../tests/packages/sqlite-profile-check.md).

`ffmpeg-catalog RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY` creates a
pinned FFmpeg 8.0.1 local media profile: FFmpeg and FFprobe share a separately
versioned musl/library runtime, with notices, upstream source and V build tools.
See the [profile](SDK.md#ffmpeg-local-media-publisher-profile) and
[qualification](../../tests/packages/ffmpeg-profile-check.md).

Software's **Launch in Terminal** action runs an installed CLI application in a
PTY within its window. `run-terminal ID [ABSOLUTE_FILE...]` provides the same
ordinary-account launch from an existing terminal; it refuses redirected input
or output. See [terminal execution](SDK.md#interactive-terminal-execution) and
[qualification](../../tests/packages/terminal-check.md).

`run-args` and `run-terminal-args` accept literal command arguments after `--`.
Use `--file ABSOLUTE_FILE` before the separator for each explicit document grant;
these grants do not append arguments. See [command execution](SDK.md#literal-command-arguments).

Software's **Launch options…** offers quoted arguments, explicit file grants,
private-data/installed-app working folders, batch diagnostics and PTY execution.
The form defaults to private data for relative outputs; CLI clients select that
folder with the additive `--data-cwd` flag. See the
[launch-options qualification](../../tests/packages/launch-options-check.md).

`compose-catalog` combines reviewed profile locks into one publisher catalog,
with separate prepared-root directories for each profile. It retains pins,
permissions and license declarations and rechecks targets and dependencies.
See [catalog composition](SDK.md#compose-application-catalogs) and
[qualification](../../tests/packages/composition-check.md).
