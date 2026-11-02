# Absent autofill service component query

`AutofillManager.getAutofillServiceComponentName()` now returns null on this
target, which has no autofill service. This matches
[AOSP API 28's absent-service branch](https://android.googlesource.com/platform/frameworks/base/+/android-9.0.0_r3/core/java/android/view/autofill/AutofillManager.java#1260).
The change appends one public instance method. All seven existing manager
methods, class metadata, callbacks and AutofillValue behavior remain unchanged.
No provider, autofill session, native binding or successful fill is advertised.

The preceding ARM run recorded an uncaught missing-method error through the GMS
synthetic API outline, `ayrh.a` and `AutofillModuleInitIntentOperation.b`, followed
by `System.exit(10)`. The GMS helper's null-component branch returns false before
provider package operations. Further operation callers, full SDK production,
ARM execution and GMS stability are separate checks.

Focused checks passed on the first attempt: ten malformed/repeated-query
refusals, five independent output controls, baseline/patched API-28 assembly,
and two DEX disassembly rounds. The oracle requires the exact null getter,
retains all original methods and metadata, and compares identical canonical
second-roundtrip bytes. The manager is outside the retained native bundle's
70 consumed classes; complete successor equality remains a deployment check.

Evidence is outside Git at
`/Users/alex/.local/state/vinix/android/autofill-service-source-check-2026-11-02-r1`.
It retains frozen provider, integration, driver and checker sources, input pins,
generated C project, guarded commands, original/patched DEX and both roundtrips.
The proof receipt hashes to
`aafe2e0dd176e4608b48ff6f697fb895b675aec2a0f4889630ef5ce1667922f7`.
Source parent before this commit is `e0960b51d056fd2cd1d211816947bc6aed5133d6`.
Provider/integration/driver/checker SHA-256 values are respectively
`6919ea259d19d0cb56fb73bba2adf63ebc1bed512d516a06d45958432839cc06`,
`673f9979b5889ea5ece5e0800392192688a9f2fdd9a1052bf727f59038f242e0`,
`0f087edb6db98f6ee0ec8e71e391809a497d4a7a66fc85b3e4c3791a4e5077c7`
and `7a1ed0f8cbadb16489f78f0efd5368d7d5596e9804d1ceee201e98c261a4c92a`.

The proof took 6.553 guard seconds, sampled 233,324,544 bytes aggregate RSS and
recorded 176,422,912 bytes detailed RSS. The compiler's largest sampled/detailed
RSS was 259,309,568/278,216,704 bytes. Every guard and child exited zero, with
complete cleanup and zero swaps, under the original 600 MiB RSS, 300-second,
512 MiB shared-growth, 1 GiB reserve, 4 MiB output and file cap 16777216 limits.
No Maps imagery, login or authentication result is claimed by these host checks.
