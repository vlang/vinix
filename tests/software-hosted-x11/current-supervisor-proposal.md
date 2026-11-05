# Inactive combined supervisor proposal

`bind-current-options.v` is **uncompiled and unexecuted**. Independent source
review covered its exact derivation from the frozen
`bind-options-compact.v` (`4ae43bc0e197ea15ecbfde302a0d4105299f628e23ffc09b43f8286023423a4b`).
This checkpoint adds maintained source for later qualification; it establishes
no source-generation, compiler, host-control, import or native result.
The repository revision before the checkpoint was
`b8eadb0a8ef4624c1db3deb5ba154bb759f24310`.

The generator would change only the independently copied private
`source/tests/software-hosted-x11/supervise.v` below
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02`.
Its original supervisor and both original wrapper files are currently unchanged:

| Private input | SHA-256 |
| --- | --- |
| `supervise.v` | `cd879181f0de1d4fee74a21e091e254bec590f68fef5d6d31d5aea8e37ede1ac` |
| `run-native06.v` | `694154cce9dd8cb216a79109154cafc81fdeea8726053ae39aa9b5f67f2889a0` |
| `run-evidence06.v` | `df20e71bde091cbea26952eedd6a9036985d5c1607e4fe67cb9a28521ebca22f` |
| Inactive generator after host-tool correction | `d3094b56ad6962428f87022767103fe43a63992e16e2926835ada4ced6bf0056` |

The proposed executable combines the original supervisor and wrapper function
bodies, with exact-count reversible function/path substitutions selecting the
qualified `check-03`, `retain-02` and `evidence-check-01`. Shared imports and one
executable avoid duplicating generated C. The existing nativeguard owner,
resource limits, cleanup, timing and receipt protocol remain in the supervisor
body. All original files would be independently copied before mutation; both
wrapper source files would remain byte-identical read-only inputs.

The two-argument supervisor entry retains its exact mode check. Three-argument
evidence and four-argument native entries first compare the entire argument tail
against the fixed vectors for the two architectures. Wrong stages, outputs,
relative paths, extra arguments and wrong or mixed architectures are refused
before bindings or I/O. Four positive and 32 negative V assertions are present
in the generator and **have not run**. Its generated source copies the same
preflight function body from the embedded generator bytes. Both wrapper branches
would use the same executable as the supervisor. The existing runtime
`expected[os.executable()]` binding captures its actual hash; there is no circular
preknown hash. The combined source remains embedded and checked.

The original inactive proposal is preserved in commit `b809d8643`. Read-only
review found that its generated global map would retain obsolete df, cp and tar
hashes and therefore fail positive bindings. The inactive correction replaces
exactly those three fixed map lines, with occurrence-count and inverse guards,
and pins the actual input paths to these explicitly reviewed bytes:

| Tool | Current SHA-256 |
| --- | --- |
| `/bin/df` | `84b985a1e447eb674bd1e8b2209dac5ca2a6803cad6cd0a9543bbd9e6b4e28bd` |
| `/bin/cp` | `a589d802b1c0dcafb205223774d7652a1d0a08b835a2dfbcf72692bfbe412880` |
| `/usr/bin/tar` | `640f174362e1c0bd27450d0cbf77583d1811f8011a6de54de81c3118b7be0863` |

No arbitrary current digest is accepted. The original fixed tool paths and argv
are unchanged, and each rebound global map key is emitted once. Read-only hashing
also confirmed the other ten global pins still match: the compiler, clang,
llvm-readelf, both QEMUs, ld.lld, xorriso, mformat, mmd and mcopy. This source
correction has not been compiled or executed. Actual final 13-control execution
and a positive bindings preflight are required before any VM; the latter still
needs a concrete reviewed invocation route. No new dispatch mode is introduced
by this checkpoint.

## Storage admission remains blocked

The consumer root retains all prior attempts and occupies 34,557,952 bytes
(32.95703125 MiB) after the evidence-checker build. Existing bounds remain
**40 MiB consumer, 254 MiB pre-final staging and 256 MiB final staging**.
The unchanged builder requires 4 MiB of consumer headroom both before compilation
and before its final 13 supervisor controls.

The original supervisor executable was 399,584 bytes, not generated C:
`/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a/native-supervision-host-01/supervise-06`,
SHA-256 `fe9b47c540ed1e202945a3bdbd84cdb56581cb17cdfbb5dc855d97e8a62e58c2`.
Its actual production argv omitted `-keepc`; no original supervisor C is retained
there. The unrelated B03 builder C is 1,410,794 bytes and supplies only a proxy.
A credible small final-C forecast cannot be derived from the binary size.

The earlier 256 KiB journal estimate also omitted the complete 120-second
observation window. Up to 122 df sets each retain three rounded files; aggregate
result, module, driver and final receipts require additional space. The sampled
40 MiB allocation cap is the actual journal bound. The current forecast cannot
retain C and guarantee the final 36 MiB control-admission threshold, so neither
the binder nor the combined executable was compiled.

The following earlier estimate is **incomplete and withdrawn as a completion
budget**. It omitted the replacement builder needed to change these limits:

| Consumer component | MiB |
| --- | ---: |
| Existing retained actual | 32.95703125 |
| Binder, preparation and source copies | 1 |
| Final combined generated C allowance | 1.75 |
| Final executable allowance | 0.75 |
| Full build journal and receipts | 1.75 |
| Required 13-control headroom | 4 |
| Subtotal excluding the replacement builder | **42.20703125** |

The existing B04 consumer builder hardcodes its 40 MiB sampled/final cap and
36 MiB admission threshold separately in compilation, supervisor controls and
module controls. A proposed 44 MiB cap with a 40 MiB admission threshold cannot
use that executable unchanged. A new source, bootstrap, generated C, executable,
input captures, compiler scratch, logs and qualification receipts must be
preserved as another phase; none is included in the 1 MiB binder allowance.

The prior B04 bootstrap provides actual size evidence:

| Existing artifact below `native-consumer-tools-01` | Bytes | SHA-256 |
| --- | ---: | --- |
| `scratch/build-supervision-consumer-01.50918.5051610416.482383976048.tmp.c` | 1,410,775 | `3d7a9a385483534b5768547a003e24c5a48f68239974e1f651a0073eb92a238b` |
| `build-supervision-consumer-01` | 377,760 | `32bd164c24dca1046601e0b5c0654d09510a1408704666cd30b19a72eb4c6a44` |

These ordinary single-link files occupy 1,794,048 allocated bytes together,
before their source, argv/environment, logs, status or temporary compiler costs.
The bootstrap argv used a 300-second gtimeout and retained C. Its recorded status
is explicitly a command observation, not a nativeguard journal or cleanup
qualification. Replacing this bootstrap with a sampled 120-second phase would
need an explicit reviewed route and its own full journal allowance; it is not
provided automatically by changing cap literals. Existing failed attempts remain
charged. A failed future attempt must stop for a fresh projection.

The separate 10 MiB staging-bootstrap root is not free storage. A read-only
`du -sk` observation reports 8,466,432 allocated bytes, leaving at most 2,019,328
bytes within that reservation. The measured prior builder C and executable alone
would leave only 225,280 bytes there. That does not cover source/receipt copies,
new caches, full observations or transient compiler output. This root also still
needs the current-profile import bootstrap; the existing `compact-import-04`
executable alone is 759,216 bytes. Moving the new builder there therefore does
not establish a fit. Any other placement must remain explicitly charged.

For scale, an additional 1.75 MiB builder-C allowance, 0.5 MiB executable,
0.25 MiB source/receipt copies and 1.75 MiB full 120-second journal would add
4.25 MiB to the incomplete subtotal, producing **46.45703125 MiB** before resolving
the actual bootstrap route and its temporary peak. These are forecasts, not a
qualified phase or a revised cap proposal.

The former 44/258/260 MiB consumer/pre-final/final option is consequently not
completion-ready. Its 257.703125 MiB aggregate arithmetic included both imports
and the existing final reserve, but its consumer allowance omitted required
builder growth. A replacement proposal must account for that phase, every
retained failure and transient, the full final-control reserve, both imports and
the existing final receipts before naming new bounds. No cap increase is
authorized or implemented; the current 40/254/256 MiB limits remain unchanged.

Before any later execution, the staging ledger must explicitly include the
changed private `supervise.v`; binder source, binaries and copies must stay inside
the charged consumer root. Qualification still requires the actual binder,
strict production executable build, all 13 supervisor controls, current-profile
import and full consumption checks, then both native guests and their 89 evidence
controls. The maintained qualified compactproof/compactui packages are unchanged.
