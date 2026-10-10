The independent J313 speaker fixture models two TAS amplifiers, their I2C FIFOs,
ADMAC sample/report rings, MCA power sequencing, and a double-precision thermal
oracle. Its V bodies preserve all 175 assertions and all 20 groups from the
1,234-line fixture frozen at `e29fe9529b8d998d28f17ac120b27fb93902c6f6`.

Run `python3 tests/apple-speakers/run.py` for the immutable C/V comparison under
ASan/UBSan. On macOS ARM64, `--host-arch amd64` also tests the actual x86 SDK and
Rosetta. `--state-dir <new-directory>` preserves generated artifacts, original
bytes, allocation-import checks and the parity receipt.

`--arch aarch64` or `--arch x86_64`, together with `--kernel-dir` and
`--guest-state-dir`, builds a static native model and requires every group marker
in QEMU. `--build-only` stops after strict compilation and linking. The fixture
retains the original two process-lifetime DMA buffers, the played-sample realloc
and final free, and the regenerated-tone malloc/free pair; generated code is
checked for exactly those sites.

The normal ARM host comparison compiles the complete unchanged production core.
An injected model never calls the real MMIO, counter, cache-maintenance or power
callbacks. For cross-architecture native model tests, `provider.py` copies the
production V provider while omitting exactly eight hardware-only definitions.
The receipt records each omitted body and its original references, hashes every
retained chunk, and rejects retained executable references. All exercised
transport, fixed-point arithmetic and thermal policy bytes remain unchanged.
These model results do not validate physical amplifiers or establish production
x86 speaker support.

`build-guest.sh` creates the separate physical-M1 sound test image; it requires
real hardware and is independent of the injected model.

The argparse and temporary-directory frontend delegates the host comparison,
allocation audit, receipts and selected native command to `run.v`. Frozen C
and V fixture bodies and their assertions remain independent inputs. Paths use
literal Unix bytes, including caller-supplied backslashes and newlines. The
unchanged platform, fixture and serial producers remain separate dependencies.
Controller qualification compares original/native command and file policies;
it makes no new physical-speaker or kernel-boot claim.
