# Fresh x86 frame baseline plan

Fresh source preparation, controller bootstrap/host controls, fixed native
source generation and both strict native bootstraps have passed. Each native
profile passed all 67 closed controls; see
[`fresh-frame-native-qualification.md`](fresh-frame-native-qualification.md)
for the pinned source bytes and external receipts. The fresh x86 frame kernel
build also passed its original controller and native guards; see
[`fresh-frame-native-build.md`](fresh-frame-native-build.md). The original full
seal, first check and root-owned independent check also passed; see
[`fresh-frame-full-audit.md`](fresh-frame-full-audit.md). Guest/performance
staging and execution remain pending. The
original baseline refusal in `frame-baseline-preflight.md` remains historical;
the separate fresh atomic success does not qualify this frame kernel.
Require root review and a reserved host phase for each remaining heavy phase.
The referenced historical frame and atomic roots and their worktrees remain unchanged.

The original plan bytes (SHA256 `c28368f7be6cebbd77befcccdaa17a3bc77d0f997d72b1b20312afc9fb956cf2`)
and checksum are preserved at
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-planning-20261104-01`.
This read-only planning input measured 16 KiB allocated/13 KiB apparent and is
outside fresh execution growth. No W/R/S or build result was created for it.

The subsequent held-plan bytes (SHA256
`104c63b05b89137cb27d52aa55fc55a4d7a1ec94e59591d73ab3b937131925b1`)
are preserved with their checksum at
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-planning-20261104-02`.
That read-only planning snapshot measured 24 KiB allocated/19 KiB apparent,
outside fresh execution growth. The setup/bootstrap/build/audit recipes below retain the
completed attempt's provenance; do not rerun them against consumed output
names. Later guest/performance and consumer work still requires a reviewed phase.

## Fixed bindings and budget

These bindings denote literal absolute argv values, not shell substitutions:

```
D=/Users/alex/code/vinix/build/peer-login-runtime-guarded-worktree
F=/Users/alex/code/vinix/build/package-alloc-track-frame-worktree
A=/Users/alex/code/vinix/build/package-audio-peer-login-guarded-worktree
W=/Users/alex/code/vinix/build/package-peer-login-frame-fresh-worktree
R=/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026
S=/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026-seal-01
C=/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v
V=/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v
CLANG=/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23
AR=/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-ar
LD=/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld
TIMEOUT=/opt/homebrew/bin/gtimeout
SEAL=/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal
PROFILES=S/native-profiles-01
NATIVE=S/native-bootstrap-01/fresh-frame-observer
INDEPENDENT=S/native-bootstrap-02/fresh-frame-observer
CHECKOUT=b262bf48f44b6cd1e9f3b73a7d8b0a079bc98943
BASE=9acefa77bee69247c837e97987a2377536aa41cc
```

W, R, S and the matching git metadata basename were absent at initial setup
admission and now exist. Require their exact canonical bindings and fresh
phase output names at subsequent admissions. Require 2 GiB free at each phase admission,
1 GiB at every subsequent observation and a 512 MiB inclusive cap for both
allocated and apparent bytes across D+W+R+S. Native build/audit phases require
live observations at most five seconds apart; limited setup/bootstrap
observations have the scope below. The 448 MiB projection comprises D 4, W 16, retained
outputs 96, concurrent intermediates 128, aggregate logs 80, inventories/seal
16, bootstraps 32, private caches 16 and reserve 60 MiB. The refused baseline
currently occupies 26,488 KiB allocated/73,957 KiB apparent, and its seal
476/463 KiB. Those measurements support sizing only; no old output is copied.

The read-only donor and fixed compiler/dependency referents are outside fresh
growth. Planning measurements in KiB allocated: F 12,824; C's tool directory
119,844; V's tool directory 119,844; LLVM 1,840,308; LLD 5,900. Declared kernel
dependency roots total 5,628 KiB including the 1,144 KiB cc-runtime donor;
the fresh private cc-runtime copy is charged inside W. These are input-root
measurements, not an assertion that every byte in LLVM is used.

Initial Git setup, source preparation, controller bootstrap/controls and native
observer bootstraps use fixed bounded direct commands. Capture fresh
admission/completion df, allocated and apparent du over every existing charged
root, log lengths, actual outer statuses and source/tool maps. Record expected
missing fresh roots before creating them. These phases make no continuous
five-second sampling, live-floor, sole-reap or arbitrary-descendant cleanup
claim. Tool-cell polling intervals are not evidence of live supervision.

The kernel build and all original complete audits instead require qualified
fixed native observers with synchronous callbacks. Record actual sample
starts/durations, raw probes, both du measures and df. Each start gap and complete
sample window, including journal writing, must be at most five seconds.
A longer gap preserves the actual result but refuses native qualification.
Retain every refusal and reject observed floor/cap breaches. The native
512 MiB ceiling reserves 1 MiB for its output tail, leaving a 523264 KiB
measured ceiling; its append-only journal is capped at 4 MiB.
Bootstrap/setup logs are capped at 16 MiB, make at its existing 32 MiB, and
audit child logs at 2 MiB. Keep the native combined 32 MiB log accounting as
well as the separate live/final audit-child bound. All attempts and failures
remain. The controller separately owns make's group and cleanup protocol;
an outer owner does not establish cleanup of separately owned descendants.

## Pristine sparse source setup

Retain each literal argv, actual output/status and environment. Each git
operation has the outer prefix below and its own 60-second bound:

```
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "60s", "/usr/bin/git",
 "-C", "/Users/alex/code/vinix", "worktree", "add", "--detach", "--no-checkout", W, CHECKOUT]
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "60s", "/usr/bin/git", "-C", W,
 "sparse-checkout", "set", "--no-cone", "/AGENTS.md", "/.githooks/", "/kernel/",
 "/tests/kernel-allocs/", "/tests/native-generators/", "/tests/linuxkpi/hosttest/",
 "/build-support/run-v-tool.sh", "/build-support/find-v.sh", "/build-support/cachecli/",
 "/build-support/cachekey/", "/tools/sourcecommand/", "/tests/kernel-symbols/symbolcore/"]
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "60s", "/usr/bin/git", "-C", W,
 "checkout", "--detach", CHECKOUT]
```

Before preparation require exact HEAD CHECKOUT, empty `git diff HEAD --`, no
untracked inputs, and empty `git diff BASE HEAD -- kernel`. Use bounded
10-second recorded git probes, matching the controller's existing probe
policy. Create only the fresh R/private bootstrap directories at admission.

The maintained V preparer is `D/tests/socket-peer-login/prepare-fresh-frame.v`,
139 lines, SHA256
`68620393ddbf4d90defcdc4c6e1393cf8046a17fa9db23d2eabc0bdb73cc9267`.
It requires the exact fresh worktree pointer/HEAD and absent dependency/output
destinations, then copies six individually pinned ordinary files from F:
four frame sources and the two maintained frame checkers. It verifies both
donor and copied bytes. Three peer files must retain their pristine b262/9ace
hashes before and after setup. It pins the controller/ABI/dylibclosure from A
without modifying A. Its only controller transformation is this full delta:

```diff
-const frame_baseline_root = repository + '/build/package-alloc-track-frame-worktree'
+const frame_baseline_root = repository + '/build/package-peer-login-frame-fresh-worktree'
```

The exact read buffer must match controller input SHA256
`20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd`,
and the old binding must occur exactly once. The fresh controller hash and
full before/after binding are retained in `R/setup-01/source-copy.json`.
All other controller bytes are unchanged. No compiler, profile, budget,
mutation control, source pin, callback or original checker is changed.

Frame4 hashes are explicit in the preparer: frame_page `be2b4cee...`, track
`23aacc0a...`, locks `74067cb8...`, slab `5c476a01...`. Unchanged peer hashes
are public `fd712e3b...`, socket `35fd5806...`, unix `5a133bfc...`; the full
64-digit values are in its maps. After setup require exactly the three tracked
frame edits, full tracked patch SHA256
`bbf47e280990b368fdd38a8917770de3024df078254a13aa116372e421fd7e25`,
and only frame_page.v as the untracked kernel source before dependencies.
Record complete source/patch/status proof outside any later sealed worktree.

## Coherent bootstrap environment and literal commands

For each bootstrap set P to its fresh dedicated directory, clear the inherited
environment and set exactly:

```
HOME=/Users/alex
USER=alex
LOGNAME=alex
PATH=/usr/bin:/bin:/usr/sbin:/sbin
V=C
VEXE=C
V_MACOS_V3_CALLER_VEXE=C
V_MACOS_V3_CALLER_VEXE_PRESENT=1
V_MACOS_V3_CALLER_VCHILD_PRESENT=0
V_MACOS_V3_NO_FALLBACK=1
V_MACOS_V3_CALLER_NO_FALLBACK=1
V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT=1
VMODULES=P/modules
V3CACHE=P/cache
XDG_CACHE_HOME=P/cache
VTMP=P/tmp
TMPDIR=P/tmp
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
DEVELOPER_DIR=/Library/Developer/CommandLineTools
```

Retain source copies, exact argv/environment, actual status, generated C and
logs. Use P=R/preparer-bootstrap-01 first:

```
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "300s", C,
 "-prod", "-nocache", "-keepc", "-cc", CLANG,
 "-cflags", "-Werror=incompatible-pointer-types", "-o",
 R + "/preparer-bootstrap-01/prepare-fresh-frame", D + "/tests/socket-peer-login/prepare-fresh-frame.v"]
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "120s",
 R + "/preparer-bootstrap-01/prepare-fresh-frame"]
```

Then P=R/bootstrap-01, compiling the actual prepared controller:

```
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "300s", C,
 "-enable-globals", "-prod", "-nocache", "-keepc", "-cc", CLANG,
 "-cflags", "-Werror=incompatible-pointer-types", "-o",
 R + "/bootstrap-01/guarded-build-check", W + "/tests/socket-peer-login/guarded-build-check.v"]
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "120s",
 R + "/bootstrap-01/guarded-build-check", "--host-controls", R + "/host-controls-01"]
[TIMEOUT, "--signal=TERM", "--kill-after=5s", "120s",
 R + "/bootstrap-01/guarded-build-check", "--closure-controls", R + "/closure-controls-01"]
```

Both host control modes must actually pass before build. Imports resolve
relative to the explicit controller path, as in its qualified bootstrap.
Preserve any compiler refusal; only a separately recorded compiler-only
correction may use a fresh attempt, without changing reviewed semantics.

## Fixed native frame profiles

After controller compilation and both host control modes return actual zero,
capture its actual binary/source hashes. The maintained V generator is
`D/tests/socket-peer-login/prepare-fresh-frame-observer.v`, SHA256
`d0c206394e78b77924d3acc22f10745f17c6a960cc9572ab8816a26f423b397d`.
Its strict bootstrap and fixed generation passed before the generated full
diff review and both 67-control suites. It accepts no operands and requires fresh PROFILES;
it cannot create a worktree, compile, build, audit or qualify a kernel.

Before generation, write the actual canonical flat string-map receipt
`S/controller-bootstrap-01-pins.json` with exactly these eleven keys:
`format` (`fresh-frame-controller-v1`), `controller_source`,
`controller_source_sha256`, `controller_binary`, `controller_binary_sha256`,
`bootstrap_actual_exit`, `source_tool_maps_cmp_actual_exit`,
`host_controls_actual_exit`, `closure_controls_actual_exit`,
`host_controls_sha256`, and `closure_controls_sha256`. The four actual result
fields must be string `0`. Paths must be the exact W controller source and R
bootstrap binary. The last two hashes bind the actual R host/closure JSON
artifacts. Encode with `json2.encode(map) + '\n'`; missing/extra keys,
noncanonical bytes and nonzero result values refuse. Populate result fields
only from actual completed commands and retain their argv/logs/status/maps;
the generator does not itself establish those commands' execution. The parent
phase plan must bind this actual receipt SHA before generation; it is not
fabricated by the generator and has no placeholder binary hash.

The generator pins the qualified native core at
`tests/socket-peer-login/fresh-atomic-observer.v`, SHA256
`a473233234928cc68a5a6d87e432c2dc34ff5ecb6d5037dfe9bd1cc4e181a006`.
It derives the expected controller source from pinned20aa with the one fixed
frame-root substitution, checks W source and actual controller/control pins,
then guards every exact source replacement/count and inverse byte equality.
It writes generated sources only under PROFILES `/primary/source` and
`/independent/source`; no 900-line source is copied into Git.

The frame changes are the fixed roots, actual controller/source pins,
`build-01`, fixed `[controller, "--frame-baseline", R + "/build-01"]` argv,
x86-only inner status/qualification checks and total 1100-second build wall.
The production clock starts before preflight/pinning/admission and the existing
final wall/tail helper runs after status writing, immediately before PASS.
Build retirement grace stays 10 seconds. Refused cleanup may extend beyond
the wall and remains refused. Keep the reviewed synthetic quiet control with
an actual pre-admission start and 900 ms wall, strictly before the one-second
periodic trigger; never reset recorded samples or broaden accepted errors.

The frame-only additions enforce each audit child's 2 MiB ordinary-log bound
inside its live callback and after cleanup, preserving the global combined
32 MiB accounting. Six frame-profile controls cover exact build argv,
x86-only receipts, total wall, numeric child-log boundaries and a real closed
child writing over 2 MiB. That refusal must retain its specific log-cap reason
and actual ECHILD/ESRCH cleanup; unrelated resource/owner errors do not count.
Each profile must pass all 67 controls (qualified61 plus6); a refusal is not a
qualified profile. The independent profile differs only in its six fixed
check-state literals and one fresh controls path.

Bootstrap the generator and both native profiles with the same strict coherent
C/clang flags and 300-second direct bounds. Native source lookup is
`-path @vlib:D/tools`; all profile outputs and private module/cache/temp paths
stay under S. Preserve direct bootstrap admission/completion-only scope and
all failed attempts. Compile primary source to NATIVE and independent source
to INDEPENDENT, run each with fixed `--controls-02`, and record actual source,
binary and control hashes. The first profile uses S check01/controls02; the
second uses S check02/controls03. Full generated diffs and actual hashes must
be reviewed before bootstrap; do not insert unknown controller pins.

Before either native control suite, require fresh `R/native-observer-01` and
create it as a canonical ordinary directory during admitted mutable setup.
Record this bounded setup operation and its pre/post observations. The native
core requires that directory for controls and build owner state; S profile
directories do not replace it. Never create it after the raw-root freeze.

The completed build used this invocation after native control review and
fresh admission; a future attempt requires separate review and fresh outputs:

```
[NATIVE, "--build-frame-01"]
```

This mode directly owns the unchanged frame controller with its original
900-second make bound. Do not add an external timeout around the native owner
or use a JS polling loop as its monitor. Keep all four-root accounting,
floors, measured ceiling, journal/log admissions, raw probe retention and
direct-leader/original-PGID cleanup observations. A successful original x86
make cleanup receipt remains separately mandatory. Native status is
provisional through the final 1100-second/five-second guards and requires
actual outer zero plus native PASS and original build qualification.

The unchanged inner make is bounded to 900 seconds with literal argv:

```
["/usr/bin/make", "-C", W + "/kernel", "-j2", "ARCH=x86_64", "ALLOC_TRACK=1",
 "PROD=true", "LIMINE_MP=0", "LINUXKPI=0", "PCI_CONFIG_TEST=0", "PCI_TOPOLOGY_TEST=0",
 "ACPI_SYNC_TEST=0", "STACK_GUARD_TEST=0", "KERNEL_LINK_RANDOMIZE=0", "VFLAGS=-nocache",
 "V=" + V, "CC=" + CLANG, "AR=" + AR, "LD_X86_64=" + LD, "LD_AARCH64=" + LD]
```

Both V executables retain SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
clang `4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`;
AR `20bf95222345e846483af09868180d0005a83f70e7df3503e25df9280333e33e`;
the LD referent `745f1b0e8809caef992e6136402561787d951cafe3d0d1736bdc7c03be41e98b`.
Preserve LD's literal spelling because argv0 selects its ELF behavior.

The controller alone creates exact links from W/kernel to repository kernel
`freestnd-c-hdrs`, `c/flanterm`, `c/lwip`, `c/uacpi`, `c/nanoprintf.h`, and
privately copies cc-runtime with complete relative bytes/modes/link equality.
Wrong links and pre-existing obj/bin/architecture runtime outputs refuse.
All source, kernel dependency, compiler and loaded-library closures, actual
environment, SDK/resource headers and host tools are recursively inventoried
before and after build under existing 120-second/250000-entry/depth128 bounds.
The same maps must compare equal; freeze them throughout postflight. Actual
generated C must pass the existing 18 frame mutation refusals and ELF machine,
track_enter and syscall_getsockopt symbol checks. This is x86 frame4 only;
there is no ARM baseline or peer ABI qualification claim.

## Original complete audit and handoff

After successful build/postflight finish every R status/report and stop all
writers. Subsequent audit logs, probes, status and every new module/cache/temp
path live under S outside R. Recheck space and unchanged checker/source hashes.
The completed original full-audit sequence used:

```
[NATIVE, "--seal-01"]
[NATIVE, "--check-01"]
[INDEPENDENT, "--check-01"]
```

The first two modes invoke exactly `[SEAL, "seal", R, S + "/complete"]` and
`[SEAL, "check", R, S + "/complete/inventory.json"]` under measured total
600/300-second walls. Root owns the third original-check invocation, with the
same check argv and 300-second wall but fresh S check02 owner state. Audit
retirement grace remains zero; final wall and five-second tail checks run
after provisional status and again after source/marker checks. Require
actual outer zero, the exact original complete-state marker and native PASS.
A provisional native status alone cannot establish PASS. Refused cleanup
may exceed its deadline and remains refused.

SEAL remains SHA256
`fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`,
source `tests/kernel-allocs/frame-page-seal.v` remains
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`.
Require actual zero, the exact complete-state PASS marker and a separate root
invocation of the unchanged original checker before any consumer migration.
Retain final manifest/qualification/source/ELF/C/source-map hashes and all
actual outer/inner statuses. An audit refusal remains a refusal; do not copy,
reseal or weaken historical evidence. Guest/performance staging and launch
require a later approved profile and slot, after the fresh original audit.
