# Checked V ARM64 interpreter generator

Continuation of 2a1191916 and the initially unvalidated d8828d2ba checkpoint.
The three previously tested helper replacements remain unchanged. The separate
`art-mterp.v` driver and `artmterp` module now compile with available latest V,
pass their full synthetic fixture, and generate all eight real ARM64 templates.
They are not integrated into the native build recipe. Assembling/linking the
generated interpreter and testing the native runtime remain pending; Google
sign-in remains unresolved and no runtime change has been deployed.

The retained source generator translates the ARM64 templates into Python and
executes that program. This candidate implements the needed template operations
directly in V: function definitions, string/boolean parameters, calls, local
assignment, conditional blocks, startswith, variable interpolation and captured
helper calls. It follows the original helper buffering/sorting, opcode labels
and alignment and empty-line squashing. It checks the packed 256-opcode table
and bounds recursion and expansion. Unsupported operations fail; no Python,
general interpreter, subprocess or runtime fallback is invoked by the engine.
The original ARM64 assembly template bodies remain external source inputs.

The committed synthetic fixture describes all 256 opcodes. Its independent
expected assembly checks parameter defaults, boolean branches, startswith,
captured arguments, local/global scope, helper order and dollar escapes.
Negative cases cover malformed opcode tables, unknown functions/variables,
recursion, duplicate definitions and invalid arguments. These fixture checks
passed. The real-header check exposed unrelated V(format) macro lists; the
generator now skips entries that do not match the original opcode pattern,
with a corresponding fixture case. All 256 packed handlers remain required.

```text
art-mterp --self-test FRESH_OUTPUT
art-mterp OPCODE_HEADER ARM64_TEMPLATE...
art-mterp --check-source OPCODE_HEADER ARM64_TEMPLATE_DIRECTORY FRESH_OUTPUT
```

The source check requires the exact eight template names, hashes all templates
and the DEX opcode header before and after generation, checks 256 unique packed
handler labels, and retains assembly plus input/output hashes. Final output is
310847 bytes. This establishes source generation and the synthetic fixture's
expected output, not byte parity against an executed Python generator or
native interpreter correctness. No Python was executed.

Native Makefile integration, dependency provisioning, the ART rebuild, signed
ARM regression and a fresh real Maps account attempt remain pending.

The first combined-helper compiler attempt, `art-mterp-tools-20261114-r1`,
reported V API/array-assignment errors. Those source issues were revised;
the next invocation was refused before launch at 1589370880 free bytes
(`disk growth budget`). A real-source generation attempt was also refused
before launch. Those are failures, not compiler or generator passes.

The first separate-driver attempt, `art-mterp-tools-20261114-r3`, was refused
before launching V at 1016029184 free bytes: `disk reserve`, exit 125,
child exit -1, PID 0, no supervised groups. Its receipt has
`cleanup_complete=false`; no child ran. Limits remain RSS 629145600 bytes,
wall 300000 ms, reserve 1073741824, growth 536870912 and output 4194304 bytes.
No cap was relaxed. These generator checks ran on the host; builder
provisioning and its VM lifecycle are recorded separately.
Space later recovered enough for guarded r4 compilation and fixture checking.
The r2 real-source check then failed on the unrelated format list. After the
selection fix, final r6 compilation passed in 1245 ms with sampled RSS
306724864 bytes. Fresh fixture checks passed in 220 ms and the complete source
check in 239 ms, all returning 0/0 with complete cleanup under the same limits.
V was 0.5.2 39e0e79, executable SHA256
6bfbbc9bb51703846e68c0733605d848e8e8f09ec8e73be0d1497f457e6fe922.

Source checkpoint SHA256 values:

| Source | SHA256 |
| --- | --- |
| art-mterp.v | e217511fc4d2b9375cb106e6bbfbea8aaa37c565e5794b9c576f1adf86737d7c |
| artmterp/engine.v | 3bfd47dd598431f66979721c1ca05b07a5f716b2fe688dce2a08793ca04db936 |
| artmterp/checks.v | d3a9122cd95ef19505ca9919d7d3217c2a2351b0ae7c719cfc772fbb8de7f0cf |

Qualified artifacts under the external state directory:

| Artifact | SHA256 |
| --- | --- |
| art-mterp-tools-20261114-r6/art-mterp | 1b6172f1d619357d24638c7b19b086fab6b68b0984339f3f7beb18e1bf799110 |
| art-mterp-source-20261114-r4/mterp_arm64.S | 4d8b124446ed87ad243470def3bd3d2bd5bf837cc4bd31bc56f5dfd20ef826da |
| art-mterp-source-20261114-r4/inputs.json | 0de5a9de10560e7c0380bd910408665f94e7d5fbafac3ea9aeba41e835bbc225 |

All logs and receipts remain under `/Users/alex/.local/state/vinix/android/`.
Passing guard receipts are `art-mterp-tools-20261114-r6.json`,
`art-mterp-checks-20261114-r3.json` and `art-mterp-source-20261114-r4.json`.
`art-mterp-tools-20261114-r3.json` SHA256 is
3f5ace85acc5bbcefcf3bfe1ac7b64a5ab404a75569fe6f8453dab03a1dd7665.
The retained ART templates are in `art-generator-inputs-20261114-r1`, and the
DEX header is in `art-header-inputs-20261114-r1`, both under the archive's
`art_standalone-e78bf68917bcaaf58fef3960cd88793b3b7f39cc/art/` directory.
