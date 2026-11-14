# Prepared ARM64 interpreter generator; validation blocked

Continuation of 2a1191916. That commit's three tested ART helper replacements
remain unchanged. `art-mterp.v` and the separate `artmterp` module are a source
checkpoint for the remaining interpreter generator. They are not integrated
into any build recipe. Compilation, tests and real-template generation have
not passed. No interpreter assembly or native runtime from this candidate is
qualified or deployed; Google sign-in remains unresolved.

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
are written but have not run. They must pass before any real-source output
can be considered for the native build.

```text
art-mterp --self-test FRESH_OUTPUT
art-mterp OPCODE_HEADER ARM64_TEMPLATE...
```

Next steps, under the original bounded-command limits: compile this separate
driver using available latest V, run its complete expected-output fixture,
generate and audit all eight original ARM64 templates with the original DEX
opcode header, and retain their input/output hashes. Native Makefile integration,
dependency provisioning, the ART rebuild, signed ARM regression and a fresh
real Maps account attempt remain pending. Source review alone cannot establish
interpreter correctness or authentication behavior.

The first combined-helper compiler attempt, `art-mterp-tools-20261114-r1`,
reported V API/array-assignment errors. Those source issues were revised;
the next invocation was refused before launch at 1589370880 free bytes
(`disk growth budget`). A real-source generation attempt was also refused
before launch. Those are failures, not compiler or generator passes.

The final separate-driver attempt, `art-mterp-tools-20261114-r3`, was refused
before launching V at 1016029184 free bytes: `disk reserve`, exit 125,
child exit -1, PID 0, no supervised groups. Its receipt has
`cleanup_complete=false`; no child ran. Limits remain RSS 629145600 bytes,
wall 300000 ms, reserve 1073741824, growth 536870912 and output 4194304 bytes.
No cap was relaxed and no VM started. The retained builder remains stopped.

Source checkpoint SHA256 values:

| Source | SHA256 |
| --- | --- |
| art-mterp.v | 63255eb181fb195738218e62fe68240939b57ec093d8c2212c193fca835cd38f |
| artmterp/engine.v | 3c7b1458a4ea57822636edcc8c3efb71cf5715a1637e8228fd87039175cab8cf |
| artmterp/checks.v | 8bc6faf665ca543a4e5cadd9984dff7dde3805dc61681e58bd2280cfc317fcdf |

All logs and receipts remain under `/Users/alex/.local/state/vinix/android/`.
`art-mterp-tools-20261114-r3.json` SHA256 is
3f5ace85acc5bbcefcf3bfe1ac7b64a5ab404a75569fe6f8453dab03a1dd7665.
The retained ART templates are in `art-generator-inputs-20261114-r1`, and the
DEX header is in `art-header-inputs-20261114-r1`, both under the archive's
`art_standalone-e78bf68917bcaaf58fef3960cd88793b3b7f39cc/art/` directory.
