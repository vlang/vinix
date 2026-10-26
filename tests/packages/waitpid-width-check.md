# Explicit C wait status width prerequisite

Source baseline: `da4593385d8d375c947e9cd941b96f18a50baf78`, with the two
maintained V sources beside this report. This is a host qualification and
AArch64 compilation prerequisite; it does not qualify guest execution.

The frozen SDK ARM01 build failed before boot when Clang compiled the actual
package client's `os.Process` path: the selected V library emitted an `i64`
status slot for C `waitpid`, whose musl declaration requires `int *`. The
retained builder makes an independent compiler-root copy, changes the status
declarations and all identified addressed status locals to `i32`, and widens
values explicitly where V helpers still take `int`. It does not suppress the
diagnostic or modify the original compiler root. Fifteen files have 29 exact
patch records and 38 replacements; count mismatches refuse the copy.

The original compiler SHA-256 is
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
its complete baseline snapshot is
`c71817ec23314dd58eedeb963c87e8b035baaabbd4eebf1eb9498ab449cf2f51`.
The builder checks every selected root entry against that snapshot and the
frozen ARM01 input map before copying. The copied snapshot remains the
baseline provenance; `changes.json` and complete overlay inventories record
the correction. All generated overlay fixture C must identify the new library
root and contain an `i32`, rather than `i64`, Process status slot.

The fixture keeps checks active under `-prod`. It verifies four-byte status
slots with adjacent canaries, exact normal exit and signal status, a
deterministically running child with `WNOHANG`, unchanged status on `ECHILD`,
public `Process.wait`, polling, `signal_kill`, repeated wait, and `os.exec`.
Child cleanup checks ownership before signaling and also covers an aborted
Process whose status has not yet been collected.

Evidence is retained, including unsuccessful attempts:

- `/Users/alex/.cache/vinix-sdk-arm-20261026-01`: original pre-boot SDK failure.
  Its existing key receipt manifest is
  `ba6bd812034e7db4ce7e5c07ac6d6df3c7bee726b2eabbd8bc11ae496f973601`.
  That run's selected inputs were unchanged; its controller also wrote a
  temporary kernel copy outside the sampled namespace because this library's
  macOS `os.temp_dir()` ignores `TMPDIR`. This remains a separate prerequisite
  for a later SDK retry.
- `/Users/alex/.cache/vinix-waitpid-width-20261026-01`: the first independent
  copy stopped at the 158 MiB sampled allocation limit before patching.
  The final observed namespace was 167,587,840 bytes, below its 160 MiB overall
  allowance. The failed copy and all bootstrap sources/C/logs are retained.
  Source allocated blocks underestimated a fresh copy of compressed files;
  no fixture or guest ran. The guard observed and reaped its child group,
  confirmed the group empty, and ended with `waitpid = -1`, `ECHILD = 10`.
- `/Users/alex/.cache/vinix-waitpid-width-20261026-02`: the revised prerequisite
  uses 384 MiB overall, a 380 MiB sampled guard, and a 4 MiB final receipt
  reserve. Its preflight counts 3,728 files and 908 directories: 180,633,176
  logical file bytes; 189,923,328 file bytes rounded separately to 4 KiB;
  3,719,168 directory reserve bytes; plus existing state and 96 MiB reserved
  for builds and evidence. This estimate and one-second sampling are
  observational bounds, not a hard filesystem allocation ceiling. Each child
  has 300 seconds, with actual `df` admission at 2 GiB and a 1 GiB floor.
  `failed-check01/` retains an initial fixture compile refusal for a nested
  variable name collision. After renaming that local, `failed-check02/`
  retains a normal runtime pass followed by production compilation refusing
  deprecated `os.execute`. The final fixture uses supported `os.exec` with a
  fixed argument array. These failures changed no overlay file; all runner
  bootstrap versions, generated C and logs remain in this directory.
  `failed-check03/` retains normal, production and sanitizer runtime passes,
  followed by a baseline ARM link refusal for an unavailable capture helper.
  The checker rejected that unrelated failure. Its fresh baseline C safely
  bridges an `i64` local through a C `int` temporary: the compiler does that
  for the builtin `&int` declaration, while the actual package's explicit
  `&i32` declaration in `audiopcm` excludes the bridge for the old `i64` local.
  The final control compiles three cases as strict AArch64 objects: the exact
  historical SDK C must refuse the known incompatible wait status pointer;
  the fresh baseline fixture must compile with its observed safe bridge;
  the corrected fixture must compile with a direct `i32` status slot.
  The historical C is pinned as
  `96942711e1c98e4045f0a2ed5310eefeca60dbd6c7c545983199234cc151824e`.
  Object compilation does not qualify static linking or ARM execution.

Final check exit: 0, observed through exec session 19358. All eleven supervised
commands had their expected status: ten exit 0 and the historical SDK object
control exit 1 at `waitpid`'s incompatible `i64 *` argument. Normal, production
and production ASAN/UBSAN runs emitted the exact success marker. Every child
group was observed, reaped and empty, with final wait -1/ECHILD 10 and no kills.
The fixed object is little-endian ELF64 AArch64 ET_REL, SHA-256
`eb304ba67b7cc2561ca270fbe897c4f2ebcca84786b0fa8cd45a743d6f462064`.
Both complete compiler maps and the selected tool maps were unchanged:

- Original root map: `84749b367916b444bef07ba2d90f85fabdc1cae79a860d69dedfa5fd9c69e6d9`.
- Corrected root map: `65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f`.
- Selected tool map: `32c19a32c62370a330e13dd20e259cad3dc6f106dd8a2b0298a0c6d5a2b1cf10`.
- Exact patch changes: `4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21`.

`qualified-source/` preserves the final builder, fixture and executable bytes;
the original `sources/` directory and earlier bootstraps remain unchanged.
Their SHA-256 values are respectively
`ddc92d70e6ad1cc674971edba4842d50b77be6d68b9fe5ff427bf07be302b51c`,
`7d175e8b4c751f9ddd7c58263cea6335ba413005827b5d9dbef75cacf5102483` and
`995dee545edcd94e13c6d54a716806457ceb0e964a6871384609068dd8bf044a`.
The final generated-C inventory records the corrected root and `i32` status
for all three current host modes and ARM; historical baseline/bootstrap C is
retained and labeled separately.

The frozen failed-copy namespace's complete content inventory is
`failed01-bundle.json`, SHA-256
`bd9e4f168ccb11ffaffc9679fb86a4883ea43172887e403eed2fe869a3d1dfb8`.
The completed 02 namespace is sealed by `bundle.json`, SHA-256
`32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976`;
the inventory excludes itself, and its command receipt is outside the sealed
directory. Final `du -sk` was 215,440 KiB (220,610,560 bytes); pre-seal actual
available space was 5,351,378,944 bytes. The independent peer reviewed the
status lifetime changes, exact patches, copy admission, source bindings and
three-case strict object control. No guest was executed.

Selected tool inventories cover the resolved Clang/lld binaries, Clang resource
headers, ordinary ARM sysroot, supervisor sources, runner and fixture. They do
not establish a hermetic host SDK, dynamic-library or implicit compiler search
closure. Sanitizer leak detection is disabled; ASAN/UBSAN check memory access
and undefined behavior. The original SDK failure is not a guest result.
