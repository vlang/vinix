# Offline ciphertext reference qualification

`show-volume-reference` and `compare-volume-references` validate complete private
CH1 records before displaying saved mapping metadata, recorded digests and full
reference fingerprints. Comparisons bind exact saved metadata and return
stable/changed findings with operational-error precedence. They read no
credentials or physical parent and publish no files. See
[the contract](../../docs/storage-volumes.md#offline-ciphertext-reference-inspection-and-comparison).

```sh
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --host-reference --work /tmp/reference-host
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch aarch64 --kernel /path/to/arm-worktree/kernel/bin/vinix \
  --reference --work /tmp/reference-arm
V=/path/to/v build-support/run-v-tool.sh tests/storage-volumes/plan_run.v \
  --arch amd64 --kernel /path/to/x86-worktree/kernel/bin/vinix \
  --reference --work /tmp/reference-x86
```

The scoped ASan/UBSan host runs existing authenticated/reference/scrub codecs,
the extended actual RecoveryIO model, the unchanged real discovery model and
new native reference validation/syntax tests. Eight MBR/GPT, 512/4096-sector and
saved-mode profiles use full unsigned-width capacities. Three different digest
records exercise every ordered stable/changed pair, inspection, same-path and
hard-link inputs, exact reports and independently computed V standard-library
fingerprints. All 32 digest byte changes, every unrepaired byte corruption on
either side, repaired-CRC canonical metadata mismatches, invalid short-buffer
sizes and unchanged caller outputs on late validation failures are checked.

The actual reader/report integration covers private ownership/permissions,
exact sizes, symlinks, missing files, directories, nonblocking FIFOs, interrupted
and short reads, metadata faults, report refusal and final flush/error failures.
Descriptor counts balance and input bytes stay unchanged. Report-ready observers
require no physical pin/probe, destination directory/lock, file write/link/unlink,
random access or KDF. The formatter boundary is injected for one refusal case;
otherwise actual report code runs, and output-finalization failures take
precedence over a changed result. Host leak detection remains separate from
measured real guest retention.

Each guest runs the unchanged manual checksum fixture and its four warmup/four
measured paired cycles, then the unchanged automatic domain/mode matrix. Real
hash commands create two additional references while a controlled physical
ciphertext byte is changed; the byte is restored and flushed afterward. Offline
inspection/comparison checks clean/changed pairs in both directions and saved
modes, exact independent fingerprints, manual/automatic cross-domain equality,
same-path inputs, malformed/privacy/mode refusal and held live status/plaintext.
One hundred warmup and one hundred measured cycles each run inspection, changed
comparison and stable comparison, giving 600 new utility process lifetimes per
architecture with no KDF in these new operations. Both phases wait thirteen
seconds before comparing every warmed slab class and retained large pages.
Both reordered second boots repeat reference queries, rediscover automatic
checksum inputs and separately unlock preserved data.

The new artifact oracle imports no producer codec. It independently constructs
ten exact original/automatic/changed references per guest, including geometry,
reserved bytes and bitwise CRC. V standard-library SHA and OpenSSL verify clean
and controlled-change extent digests and all reference fingerprints. Existing
five artifact oracle sources remain unchanged. Complete utility and selected
guest C receive allocation audits and independent lifetime review. Frozen
isolated ALLOC_TRACK kernels remain unchanged; this feature changes no kernel
implementation.

## Qualification on 2026-10-14

`host-2`, `arm-4` and `x86-2` exit receipts are zero. The scoped host passed
ASan/UBSan without sanitizer or undefined-behavior errors; all four guest boots
passed. Production and selected guest sources stayed unchanged across successful
runs. The ARM harness addition was exercised by both final ARM boots; host/x86
workload bodies were unaffected.

| Guest | Warmup + measured cycles | New utility lifetimes | Slab classes with zero delta | Large pages before → after |
| --- | --- | --- | --- | --- |
| ARM64 | 100 + 100 | 600 | 18 | 72 → 72 |
| x86_64 | 100 + 100 | 600 | 14 | 191 → 191 |

The new cycles perform 200 inspections, 200 changed comparisons and 200 stable
comparisons on each architecture. The preceding unchanged manual checksum
cycles also passed with sixteen process lifetimes/eight real full-profile
32-MiB KDFs per architecture and the same flat retention counts. Automatic
matrix creation/verification and separate held-descriptor cases precede the
new measurements. The previous automatic retention workload is not rerun by
this selector.

Fifteen independent persisted artifact oracle invocations passed. The two new
oracles checked ten exact original/automatic/changed references and all their
fingerprints per guest, using independent CRC and V/OpenSSL SHA. All nine
preceding artifact modes passed through unchanged oracle sources: automatic
checksum references, manual checksum references, ordinary VC1, recovery VR1,
automatic/manual scrub findings, recovery growth, recovery credential rotation
and sealed recovery. The complete restored extent SHA is
`115d50809715a805656e2c32b2d84ce5b4df581c65e1ec9b4523df3f9e4a6748`;
the controlled changed extent SHA is
`a45c3043d314e557b22fa0a7dc53957b2dd84154fedd0865703a1796c63bbc25`.

Initial host/guest compilation caught a missing explicit unsafe borrow for the
stack after-record pointer. It was corrected before successful qualification;
those attempts remain retained. ARM attempts 2 and 3 refused nonce acquisition
in the unchanged fixture setup because CPU timing jitter failed its entropy
health check, before the new reference commands ran. The public ARM harness now
supplies the host-backed VirtIO entropy device used by the normal AArch64 runner.
The existing kernel already supports that device; entropy health checks and
production/guest code remain unchanged. The successful final ARM run qualifies
this harness addition. Earlier failed attempts do not count as qualification.

Independent review checks complete private reads/validation before output,
transactional decoded outputs, exact metadata binding, complete fingerprints,
stack borrows and status 1 before a changed result. All 288 prior production
bodies/constants remain unchanged apart from dispatcher/usage additions.
Exactly three new allocation-free offline functions reuse the unchanged private
reader, public geometry validator, fingerprint SHA and output finalizer.
Eleven RecoveryIO and four actual discovery test bodies match their public
sources after explicit fixture transformations; forty-seven RecoveryIO and
eight discovery generated C bodies match normalized production. Both full
targets are identical and allocation-free; selected guest programs pass
allocation audits. Their original manual and automatic matrix bodies remain
unchanged.

The review found no unresolved correctness or lifetime issue, and verifies the
ARM entropy row against the normal runner and unchanged kernel consumer. The
public/private controller differs only by the documented transport adjustments.

Retained evidence under `logs/storage-reference-work` includes successful
receipts, failed attempts, full generated C, physical media, compressed closed
boot images with original SHA/length and decompression receipts, independent
oracle outputs, final source copies, frozen kernel/input receipts, review and
SHA-256 manifests. Physical media and generated C remain unchanged by compression.
The V transport copy changes only its private bootloader-cache path and existing
QEMU foreground/worker priority wrapper. Its owned RAM compiler volume is
released before archiving evidence.

This is a scoped host and disposable QEMU matrix; full native, desktop,
saved-plan and physical hardware qualification remains separate. Results
describe recorded references, without authenticating replacements, establishing
current disk contents or inferring timestamps. References must stay quiescent;
two private pins do not provide a simultaneous snapshot.
