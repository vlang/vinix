# Repository URL syntax agreement

`pkgprotocol.valid_repository_url()` is the shared, allocation-free syntax guard
for public repository proposals, previous repository identities, and service
configuration admission. It borrows the URL and preserves its bytes.

HTTPS base URLs require a nonempty authority, balanced nonempty host brackets,
an optional decimal port in 0..65535, and complete `%HH` escapes. Credentials,
raw whitespace/control bytes, backslashes, queries and fragments are refused.
Nondefault, zero and leading-zero ports remain accepted. Brackets delimit a
literal host; this guard does not validate IP addresses or resolve names.
HTTPS URLs may contain at most 4096 bytes. Acquisition still appends the fixed
index names after removing trailing slashes.

`file:///` paths retain the service's existing 1024-byte suffix bound and literal
path behavior: spaces, shell punctuation, percent signs and Unicode remain
unchanged. Empty, dot, parent and trailing-slash components are refused. No
percent decoding or shell evaluation occurs.

Run the V host driver from the repository with the pinned compiler:

```text
VEXE=/absolute/path/to/v V_MACOS_V3_CALLER_VEXE_PRESENT=1 \
V_MACOS_V3_CALLER_VCHILD_PRESENT=0 V_MACOS_V3_CALLER_VEXE=/absolute/path/to/v \
V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 \
/absolute/path/to/v -backend c -keepc -cc /opt/homebrew/opt/llvm/bin/clang \
  -gc none -manualfree -prod -path '@vlib|@vmodules|.|./tools/accounts' \
  -o /new/path/repository-url-build tests/packages/repository-url-build.v
/new/path/repository-url-build /absolute/path/to/v /new/path/qualification
```

The driver requires production compilation so its embedded source is immutable,
captures the bounded project source inventory before building, copies those
sources, and rechecks source sets, bytes, compiler executables and copies after
execution. It retains literal build/run argv, generated C, binaries, logs,
source/artifact manifests and a result receipt. Clang currently uses the local
Homebrew path shown above; its resolved executable and digest are recorded.

The [retained result](results/2026-10-23/repository-url.json) records five focused
modes: normal, production, tracked normal, tracked production and ASan/UBSan.
Each runs 1,000 valid/refused URL matrices; tracked modes retain zero bytes and
records. Explicit checks remain active in production. Exact HTTPS 4096/4097 and
file-suffix 1024/1025 boundaries cover SDK current identity, file previous
identity, and actual service configuration admission.

Actual normal and production CLIs each run 48 accepted text/JSON observations,
88 malformed refusals and two missing/corrupt configuration controls against
fresh/existing package roots. Literal URL round trips and complete fixture
entry/content snapshots must agree after every outcome; package stores remain
uninitialized or unchanged. These commands perform no repository acquisition.

This qualifies host URL syntax agreement only. It does not establish URL
resolution, network/TLS behavior, publisher enrollment or authority, target
execution, or full SDK acceptance. Project sources and V/Clang executables are
pinned; imported vlib/thirdparty, headers, linker and transitive tools are not
frozen. The run is not a hermetic or reproducible-build qualification.
