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
| Inactive generator | `798d4667aaa493776d209cc82711e97c8ff92314d6292cc40f1de858c14195fb` |

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

One **unapproved budget option** for later review is:

| Consumer component | MiB |
| --- | ---: |
| Existing retained actual | 32.95703125 |
| Binder, preparation and source copies | 1 |
| Final combined generated C allowance | 1.75 |
| Final executable allowance | 0.75 |
| Full build journal and receipts | 1.75 |
| Required 13-control headroom | 4 |
| Forecast total | **42.20703125** |

A 44 MiB consumer option would retain margin and a 40 MiB admission threshold.
It would add 4 MiB to the complete staging forecast: 31 MiB frozen tools,
44 MiB consumer, 10 MiB bootstrap, 16 MiB observers, 164,036,608 rounded bytes
for both imports, 16 KiB import directories and 256 KiB private sources total
270,221,312 bytes (**257.703125 MiB**). Preserving the existing 2 MiB final
reserve would require 258 MiB pre-final and 260 MiB final bounds. No such increase
is authorized or implemented. The allowances remain forecasts; actual admitted
phases must measure their outputs and refuse on a cap or free-space violation.

Before any later execution, the staging ledger must explicitly include the
changed private `supervise.v`; binder source, binaries and copies must stay inside
the charged consumer root. Qualification still requires the actual binder,
strict production executable build, all 13 supervisor controls, current-profile
import and full consumption checks, then both native guests and their 89 evidence
controls. The maintained qualified compactproof/compactui packages are unchanged.
