# Versioned single-cluster vertex start

Native G13 now writes the non-clustered vertex-start marker as **1 on firmware
13.5**, while preserving **0 on 12.3**. The packaged
[Asahi render builder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs)
uses `!clustering` starting at 13.0 beta 4 and zero in the older record. Vinix
already requires exactly one cluster in this preparer. Its version converter
places this word at `0x188`, after the inserted counter and notifier pointer.
The generic converter still preserves its input word.

The initializer and converted record also remain on the stack through their
synchronous writer/copy calls. Native C previously allocated two implicit
temporary copies. The conversion result needs a raw `voidptr` address binding;
an intermediate typed pointer still caused V to box it, despite lower compiler
allocation counts. Narrow unsafe scopes permit explicit stack addresses without
nested unsafe expressions. Neither pointer is retained after the call.

Validation passed:

- 12,000 ASan/UBSan byte-exact cases execute the actual native initializer and
  writer with production firmware records/conversion. They cover both ABIs,
  zero/one/sixteen attachments, full-width counters and event generations,
  varying VM/slot/address values, four destination alignments, every padding
  byte and complete surrounding guards. Stack-use-after-return detection is on.
  Existing independent work-command layout/translation tests also pass.
- The exact raw baseline `g13.v` builds and fails at the 13.5 marker: zero versus
  the required one at offset `0x188`. Source, runner, binary and failure remain
  retained. The earlier marker-only C fails the expanded storage checker.
- 37 V test files, selected primary-source gates and the strict native ARM C
  checker for 111 helpers plus its negative selftest pass. The checker now
  includes the vertex writer and converter without allowing heap temporaries.
- Root native-C review confirms two removed `memdup` sites and otherwise
  unchanged allocation/free and BO reference site counts. Converter, compiled
  batch publication, render cleanup/reaper and compute preparation bodies match
  preceding C. Independent lifetime review approved source/C/ELF hashes below;
  the preparation frame decreases from 8,720 to 8,432 bytes, and the writer's
  frame remains 480 bytes. Whole-call-chain stack use is not established.
- Existing async/scheduling, lifecycle/BIND/UNBIND/timestamp/GEM/GET_PARAMS,
  wait/syncobj, wire, fence, VM and production PTE regressions pass. PTE tests
  use `--sanitize`; sanitizer linkage receipts for the new fixture and layout
  tests are retained.
- Isolated ARM and clean ordinary x86 builds pass from
  `cff4fea9a75754835f4d35a9fadb5f19920ec493`. ARM includes the one `g13.v`
  overlay; ordinary x86 excludes native AGX. Exact overlay snapshots are retained
  for both, with `LD_X86_64=ld.lld` used for x86.

Unchanged allocation allowance audits **still fail** on baseline and feature.
ARM counts fall from 383 to 381 across 828 sources; x86 remains 289 across 813.
Exactly two `g13.v` temporary-copy sites disappear; all other per-file/kind counts
match. No allowance was changed. Native generated C separately confirms the
copies are gone; compiler counts do not measure native heap rates.

Fresh heads: Omarchy `07460209733354e3ea9b2b4aa3eaae4e7a307210`, packages
`8e174b0864ffef0c7459cf302cdd4fd5422992b8`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit: `not_equivalent`
(exit 1); selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-vertex-marker-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. Marker-only, rejected typed-pointer and compile-failure
diagnostics are preserved. `completion.txt` binds eight source paths and two
reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `6bce93a37a278171b7b39cba434c699a846a5b044f5855a22fc18da1af683e51` |
| `bundle.tar.gz` | `b142728b50b1dcdfe5302a28b20ae8beb2579ef70f1c47c0a81cf34f4d26aaa7` |
| `bundle/vinix-aarch64` | `ce28ee0d5d3b7375b059f4fbe5696d85decfc898028c3cf609b4b9b5b9f4e9db` |
| `bundle/vinix-x86_64` | `50a47bc44973711ffad6d1923d25a8e8c0dc8f5eb3f551d5641c22d0f98540d9` |

Approved `g13.v` SHA-256:
`16316e3bedf071df9bd885fa06599d7ca5a3b8f182f0b4c901d385b476e8d280`.
Native ARM C SHA-256:
`ec427a86a554f256be49954e4a2dd4219b0a77bc7a44bf653f6a09e80449ad78`.

Host records inject addresses and state; the complete allocating job preparer
and firmware interpretation are not executed. Multi-cluster rendering,
ABI/Mesa, reservation fences, retained queues, cumulative timelines and other
listed parity gaps remain open. Unrelated native heap copies remain. No GPU
execution, native hardware test, Vinix/QEMU boot, reboot, SSH or deployment
occurred.
