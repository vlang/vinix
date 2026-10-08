The four independent audit-generation regressions are maintained in V. Their
original C syntax caller remains byte-for-byte unchanged and receives no C
migration credit. V owns fixture setup, mutation, command classification,
assertion predicates and scratch retirement. Python retains unittest discovery,
the imported audit API, stdlib mock and assertion formatting, and process/error
transport. Compiler observers validate generated headers before the compiler
executes, including nested assertion callbacks.

Qualification compares the frozen full original four cases with the native
cases on ARM, x86 and ASan/UBSan. The current production bounds dependency
cannot see the original Python upstream-verification mock across its native
process boundary. Both original and native therefore retain the same two
existing failures; the two malformed-metadata cases pass. No source headers,
compiler assertions or warning policies were changed to obtain a passing run.

A separate cache-only reference uses the unchanged frozen surrounding bounds
helper and digest primitive. All four original/native cases pass there with
the real original C caller and compiler. That result establishes fixture
equivalence; it is not a pass for the current production dependency, a full
i915 audit, a kernel build or a guest workload. Forced setup, callback, cleanup,
pipe-close and controller-retirement failures also preserve exception identity
and retire their scratch owners after reaping the controller.
