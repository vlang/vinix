The generated-code and CPU-assembly checks are complete native V commands:

```sh
tests/syscall-policy/run-host kernel/obj/blob.c
tests/execute-only/check-generated kernel/obj/blob.c
tests/mounted-disk-policy/check-generated --arch=aarch64 kernel/obj/blob.c
tests/cpu-mitigations/check-assembly
```

The four `*-main.v` entries invoke `policyhost` directly. V owns argument parsing,
strict UTF-8 reads and universal newlines, checked writes, private fixture
directories, compiler processes, inherited streams and cleanup after compiler
or fixture errors. Native process helpers preserve the calling host architecture
and unbounded production deadlines. Cold invocation follows
`build-support/run-v-tool.sh` and `find-v.sh`; set `V` to choose a compiler.
The retired Python import/exception/callback bridge is no longer required.
`policy_query.v` remains a native diagnostic interface for source extraction and
fixture content; it performs file and process operations directly.

Production-function extraction, Unicode 13 allocation guards, privileged PAN
replacement and independent C fixture literals retain their original behavior
and assertions. The ARM execute-only extraction also includes the file-state
bit definitions now used by the generated production function. The nine
previously qualified ARM/x86 fixture contents retain their exact hashes and
lengths. These C fixture constants receive no kernel C migration credit.

The assembly command preserves privileged-instruction adapters, 15 register
thunk probes, the scheduler resume probe, ELF toolchain arguments and Rosetta
execution. V's `math.big` converts LLVM symbol addresses to decimal without
narrowing them. The original assembly and C assertions remain unchanged.

The related `tests/cpu-mitigations/check-linked` command scans real LLVM
disassembly with the original Unicode word/whitespace semantics, first twenty
raw-branch failures, unresolved-thunk checks, required scheduler symbol and
minimum one hundred thunk branches. Its independent rejection tests cover
Unicode boundaries, cross-line whitespace and greedy matches.

All five commands and the diagnostic query build on ARM, Rosetta x86 and ARM
ASan/UBSan. Native qualification runs the original sanitizer fixtures against
current ARM and frozen x86 generated C, executes the production assembly
adapters, checks a cached production x86 kernel (1,549 thunk branches), and
verifies twenty-one compiler/fixture failure retirements. Cold entrypoints pass
outside the checkout. Input hashes and results are recorded locally in
`/tmp/vinix-gpolicy-qualification.json`; the V qualification driver is
`/tmp/vinix-gpolicy-qualify.v`.

These host-command changes claim no fresh kernel build, guest boot or hardware
validation. The old `build-amd64-kernel/bin/vinix` artifact correctly fails the
linked checker because it contains raw indirect branches; it is not the cached
production kernel used for the positive check.
