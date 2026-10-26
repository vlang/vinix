# Native audio preparation checkpoint

The ARM audio controller can build and seal its eight target programs without
booting a guest. `--prepare-only` writes `preparation.json` and prints its SHA-256.
Review that digest and the complete retained preparation before executing:

```
audio-runtime --verify-prepared /absolute/preparation --prepared-sha256 REVIEWED_SHA256
audio-runtime --resume /absolute/preparation --prepared-sha256 REVIEWED_SHA256
```

Verification is read-only. Resume validates the original preparation, claims
`run/` exclusively and uses the prepared programs with the compiled scenario
table. It never calls a compiler or rediscovers the host. Used or changed trees,
receipt mismatches and command-line overrides fail before execution. A failed
attempt retains its run claim. Only the existing three-scenario gate can write
native qualification; preparing or verifying a basic-only tree cannot qualify
audio. The existing one-shot x86 path is retained.

The inventory includes file bytes, directory and file modes, empty directories,
all eight compiler traces and saved objects, the actual guest root, captured
loader and named runtime tools. Symlinks and special entries are refused. The
controller also binds source/current-controller bytes, generated C, artifact
maps, reviewed SO_PEERLOGIN kernel evidence, explicit runtime paths and selected
scenarios. Resume requires the original inputs to remain unchanged; QEMU and
host dynamic dependencies retain their observed host paths. This is an observed
input checkpoint, without a hermetic or reproducible toolchain claim.

Host validation passed at source baseline
`d366ee8810dee8f518c901008a779b1f53bd7ffc` plus the five maintained V source
changes accompanying this report. All four host tools built with pinned V
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
LLVM 23.1.0 clang, `-prod -nocache -keepc -backend c`, and explicit `VINIX_ROOT`.
The 88 preparation controls and existing 34 strict ARM evidence controls passed;
both control runs retained identical selected-input hashes before and after.
Independent source review found no remaining blocker within the reviewed-digest,
stopped trusted-host scope. No target build, guest boot or native audio
qualification was performed for this change.

Complete preserved attempts and final receipts are outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/`:

- `prepare-host-03/host-build.json` records the final four builds, literal
  commands, tool/environment pins, generated C and source inventory. Its SHA-256
  is `28efbc0fa1d87735a757c77ffdd388109a3d4c098704bdf2c6c38297d8685b90`.
- `prepare-host-03/bundle.sha256` seals the host builds before the controls:
  `51ee84fea05517c059915a541e63dbf1cfb84e0d0f0d16d6875f8126bf3cbaed`.
- `prepare-host-validation.json` inventories all 22,666 entries in preserved
  `prepare-host-01`, `-02`, `-03` and the named external V recorder helpers,
  including literal internal symlinks without traversal. Two stopped-tree
  observations matched, and a separate verify invocation passed. SHA-256:
  `a2b9e1153f1443ecfaf6eefc927abe86f8f0bfd6d3f455aee81a58d63226f209`.

Attempt 01 is superseded. Attempt 02 built successfully but its source-root
mutation control also changed checkout discovery, producing a different correct
refusal than the test expected. The final checker binds checkout discovery to
its compiled source location. Attempt 02's logs, receipts and immutable source
snapshot are preserved; its hardlinked synthetic source leaf was detached and
restored to the exact as-run bytes, as documented beside that attempt. Attempt
03 passed all controls. The original `current-main-host-01` manifest and every
listed artifact were also reverified unchanged. The final inventory and helpers
bring new retained allocated state to less than 100 MiB, excluding preexisting
kernel and source hardlinks. Host SDK and original tool dependencies remain
observed inputs rather than a hermetic compiler closure.
