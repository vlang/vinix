# Fake G17 execution backend

Vinix keeps the Mesa-facing DRM lifecycle above generation-specific GPU
execution.  VirtIO-GPU/VirGL is the accelerated VM reference backend, native
AGX remains the hardware backend, and fake G17 execution stops at the recovered
HAL300 command boundary:

```text
Mesa / applications
        |
Vinix DRM: GEM, VM, sync objects, fences, queues, teardown
        |
        +-- VirtIO-GPU -- VirGL -- host GPU
        |
        +-- AGX -- G13 firmware -- M1
        |
        `-- G17 command builder -- HAL300 register streams
                                      |
                                      +-- native PMP/RTKit/UAT/G17 firmware
                                      `-- fake verifier -- synthetic fence event
```

The fake backend is not a G17 emulator. It proves that a command builder
produced the expected bytes and that the ordinary Vinix queue/fence lifecycle
handles success and failure. It cannot prove firmware boot, real UAT mappings,
hardware register semantics, or acceptance by G17 firmware.

`gpu.agx.submission` is the generation-neutral boundary immediately below the
Asahi ioctl. It gives native G13 and fake G17 identical command-array framing,
barrier and size validation, sync-object lookup, and output-fence installation.
Its `gpu.agx.render` and `gpu.agx.compute` payloads share `gpu.agx.command`
attachment staging, which copies every nested attachment array exactly once
and converts byte sizes to the cache-line count required by G13 while retaining
the original byte sizes used for fake-VM bounds checks. Both backends consume
the same immutable command and sync types and never follow userspace pointers
after staging; waiting and execution remain backend-specific.

`gpu.agx.vm` separately owns the pure 16 KiB, 39-bit AGX address-space
contract and operation-specific GEM_BIND validation. `FakeG17Vm` implements it
with retained software mappings and bounds checks; native UAT implements it
with real page tables and firmware-visible invalidation. The common module has
no import of either implementation or any hardware facility, so using it does
not create a route from fake G17 to MMIO, DART, PMP, or RTKit.

`gpu.agx.bo` owns the per-open GEM handle table, PRIME import references, and
mmap authorization shared by both backends. It intentionally has no internal
lock: the owning DRM file serializes table changes with its existing lock so a
handle close and backend-specific mapping cleanup stay atomic. Fake G17 drops
software mappings immediately; native G13 retains mappings that an in-flight
firmware job may still dereference.

The fake path has one documented lock direction: global file map, per-file,
then fake VM. The global lock is released before file teardown starts; VM
methods never call back into the file or common BO table and release their VM
lock before final GEM references are dropped. The common BO layer therefore
does not acquire a backend mapping lock or decide when a mapping disappears.

## Verification contract

`kernel/c/agx_fake_g17.c` checks the four-pass 3D register-list layout already
recovered and ported in `gpu.agx.fw`:

- command and descriptor bounds;
- each stream's exact GPU address;
- entry-count/byte-count agreement and the `0x700`-byte pass limit;
- descriptor summaries, including their reserved bytes;
- exact path-specific pass and entry ordering;
- HAL300 selector and mode fields;
- template-preserved bits under an explicit mask;
- encoded values under an explicit 64-bit mask;
- address-valued entries against live GPU-VA ranges and alignment;
- every Mesa-derived descriptor resource against one live FakeG17VM BO range,
  including the binding's read/write permission; and
- every resource with a recovered native member against the exact GPU VA
  stored in that descriptor member.

Descriptor provenance is an explicit kernel/verifier ABI. Scalar defaults are
`constant`; direct UAPI state is `Mesa-command`; attachment ownership is
`BO/resource`; translated pointers are `GPU-VA`; layout values are
`format/stride`; and scheduler, firmware, or physical-only values are
`external-hardware`. The current Mesa resource references use a `PENDING`
descriptor member rather than inventing a mapping from Apple's proprietary
payload layout. They still have executable bounds, BO identity, and access
checks. When a native member is recovered, replacing `PENDING` with that member
automatically turns on descriptor-value verification.

The sidecar also normalizes Mesa's USC-relative program fields before VM
validation. Vertex and fragment helper programs are their respective USC base
plus the UAPI offset with bit zero removed; load, store, partial-reload, and
partial-store pipelines use the fragment USC base with their low three flag
bits removed. These derived addresses must resolve to live read bindings even
while their native G17 descriptor members remain `PENDING`. Sampler-array
ranges cover all eight bytes of every AGX sampler descriptor rather than only
one byte per sampler.

Eleven resource identities now cross the final descriptor boundary as a
deliberately scoped bridge. The TA encoder pointer is written at `0xfe0`; the
fragment load/store pipeline addresses are written at `0x610`/`0x768` with
their bind values at `0x608`/`0x760`; and depth load/store planes are written
at `0x668`/`0x670` with their metadata planes at `0x6e8`/`0x6f0`. Stencil
load/store planes use `0x680`/`0x688`, with metadata at `0x710`/`0x718`. Each
resource value is checked both against its live FakeG17VM binding and against
the exact descriptor member. These mappings agree across the recovered G17
selector/value graph, the color/depth/stencil resource traces, and m1n1
`940439`'s independent Asahi register-list producer. This does not identify the
global selector address space, and no partial-pipeline, partial-depth, or
partial-stencil member is promoted by analogy.

The expected-write list is deliberately path-specific. The recovered 314
virtual encoder call sites cover 3D, TA, FastBlit, and CL; they are not 314
writes that every render must execute.

`tools/agx-re/compile_fake_g17_plan.py` independently compiles a concrete 3D
trace from the UUID-pinned recovery output, an encoded command, and its staged
descriptor. Each pass must be an exact path through the recovered emission
CFG. Constant and descriptor-rooted expression values become full-mask golden
values. Values rooted in external channel/accelerator objects remain explicit
zero-mask entries instead of being guessed. The command-pool template bits are
recorded for diagnosis but remain unconstrained until their initial contents
are independently recovered.

`tools/agx-re/encode_fake_g17_3d.py` is the host reference encoder. It evaluates
the recovered predicates into one concrete 3D path per pass, encodes recovered
selector/mode/value formulas, publishes the four descriptor summaries, and
then round-trips the result through the plan compiler. Expressions rooted in
the channel or accelerator are never guessed: the caller must provide their
branch outcomes or values explicitly. A captured command-pool template is
preserved under the recovered template mask. A zero template is available for
fake execution only and is not evidence that those bits are valid on hardware.

`tools/agx-re/generate_fake_g17_3d_encoder.py` translates that same recovered
graph into the freestanding, allocation-free
`kernel/c/agx_fake_g17_encode.c`. The generated encoder contains no JSON parser
or dynamic expression interpreter: descriptor/command expressions are emitted
as checked integer operations, graph successors are direct branches, and the
five external values plus the one external decision live in a fixed input
structure. `gpu.agx.fake.encode_fake_g17_3d` exposes it to the V backend and returns the
exact golden writes consumed by `submit_fake_g17`.

`gpu.agx.fake.verify_fake_g17` is the V adapter. `gpu.agx.fake.submit_fake_g17` first installs a
normal `WorkItem` in the shared `WorkQueue`, verifies the encoded command, and
then injects either a successful completion or a channel-error completion.
That signals the same `DmaFence` objects and exercises the same queue teardown
bookkeeping as a hardware completion.

## Run the host test

The host test compiles the exact allocation-free C verifier linked into the
kernel together with the recovered encoder. It covers successful traces, every
validation class, a 314-entry stress trace, and all 16 combinations of the
three descriptor-controlled branches and external channel branch. Stable
whole-buffer hashes produced by the separate Python reference make the C
encoder comparison byte-exact:

```sh
./tests/agx-fake-g17/run.sh
SANITIZE=1 ./tests/agx-fake-g17/run.sh
```

Compile the kernel-side V adapter as part of the normal AArch64 build:

```sh
make -C kernel ARCH=aarch64
./tests/agx-vm/run.sh
```

Regenerate or verify the checked-in freestanding encoder after recovering a
new ABI:

```sh
make -C tools/agx-re -f GNUmakefile generate-fake-g17-encoder
make -C tools/agx-re -f GNUmakefile check-fake-g17-encoder
```

Compile a verifier plan for a captured or Vinix-generated command with:

```sh
python3 tools/agx-re/compile_fake_g17_plan.py \
    --abi tools/agx-re/build/recovered-g17-abi.json \
    --command command-3d.bin \
    --descriptor descriptor-3d.bin \
    --command-gpu-address 0x700000000 \
    --output fake-g17-plan.json
```

The output includes source UUIDs and SHA-256 hashes, the selected producer
offsets for every pass, C-verifier-compatible expected-write fields, and an
honest recovered/external value coverage count.

Build a fake-only command directly from the recovered graph with:

```sh
python3 tools/agx-re/encode_fake_g17_3d.py \
    --abi tools/agx-re/build/recovered-g17-abi.json \
    --descriptor descriptor-input.bin \
    --command-gpu-address 0x700000000 \
    --zero-template \
    --externals fake-g17-externals.json \
    --command-output command-3d.bin \
    --descriptor-output descriptor-3d.bin \
    --plan-output fake-g17-plan.json
```

Use `--template captured-command-pool-slot.bin` instead of `--zero-template`
when validating captured template bits. External inputs are keyed by recovered
producer offset and may be a scalar shared by all passes or a four-item array:

```json
{
  "decisions": { "0x2410": "fallthrough" },
  "values": {
    "0x1964": 0,
    "0x1b04": 0,
    "0x1bc4": 0,
    "0x2148": 0,
    "0x2394": [0, 0, 0, 0]
  }
}
```

With a zero descriptor and the fallthrough path above, the current recovered
ABI emits 94 entries per pass: 376 writes total, 356 with recovered values and
20 explicitly external values. These zeros make a deterministic verifier
fixture; they are not recovered hardware values.

## Run the Mesa lifecycle smoke test in a VM

The fake render node is opt-in and software-only. Boot it with enough RAM for
the desktop initramfs and the staged Mesa Asahi runtime:

```sh
./run-aarch64.sh --serial --fake-g17 --mem=8192
```

At the Vinix prompt, run the three lifecycle-only depth/stencil cases:

```sh
/usr/bin/run-gl-triangle-agx --submit-only --depth
/usr/bin/run-gl-triangle-agx --submit-only --stencil
/usr/bin/run-gl-triangle-agx --submit-only --depth-stencil
```

The same check can be run non-interactively from the host after building the
AArch64 kernel:

```sh
python3 tests/agx-fake-g17/run_vm.py
```

The runner creates scratch disk/NVRAM files by default, waits for the guest
shell, and runs depth-only, stencil-only, and packed depth/stencil FBOs. It
checks the exact Mesa renderer, requested attachment bits, depth/stencil plane
and metadata presence reported by the kernel, and render/fence completion for
all three cases. It then interposes Mesa's real Asahi ioctls in five adversarial
runs: an overlapping bind must fail, bind/unbind/reuse must preserve a valid
submission, a referenced depth-metadata BO must be rejected when it is either
unbound or rebound read-only, and a valid in-flight job must retain its mapping
after the corresponding GEM handle is closed. In the lifetime run, unbind,
queue destruction, and reuse of the occupied GPU VA must return `EBUSY`; the
same VA is then rebound to a different BO after synthetic completion retires
the old mapping. The interposer lives entirely in the test process; the fake
kernel exposes no fault-injection UAPI.

After observing the expected `EINVAL` in either invalid-resource run, the
interposer exits the faulting process before Mesa can wait forever for a fence
that was intentionally never created. Those runs prove kernel rejection and
fd/process teardown safety; they do not claim Mesa gracefully returns from a
rejected submission. Set `VINIX_BOOT_DISK` to reuse an existing test image or
`VINIX_FAKE_G17_VM_TIMEOUT` to change its 180-second deadline.

Mesa should identify the renderer as `Vinix Fake G17C (M5 Max ABI)` and report
that the render submit and fence completed successfully. The fake kernel sets a
Vinix-private compatible feature bit; stock Mesa safely ignores compatible bits
it does not know, while the pinned Vinix Mesa patch uses this bit only to change
the public renderer string. M5-compatible parameters remain in place so Asahi
can initialize. Fake submissions call the same recovered descriptor initializer
as the native G17 backend, so the VM covers its bounds/overlap-checked scalar
manifest instead of a fake-only copy. The first kernel message for each case
also includes the staged Mesa fragment command ID, framebuffer dimensions,
number of independently checked resource references, and whether depth/stencil
data and metadata addresses crossed the proven descriptor members.
This exercises the Asahi DRM ioctl layout, shared render/compute command
normalization, immutable attachment staging, per-file GEM and VM ownership,
mappings, contexts, queues, sync objects, the generated G17 encoder, the
independent verifier, synthetic completion, fence waiting, and process
teardown.

Verification remains synchronous, but a verified render now stays installed in
the common WorkQueue until a delayed completion worker signals its DMA fence.
During that interval the fake VM pins its mapping graph, GEM_CLOSE retains the
closed object's backing reference, and unbind and queue destruction are
rejected. Completion releases the VM pin, retires mappings belonging only to
closed handles, and wakes Mesa's normal fence wait. This deliberately exercises
handle, mapping, job, queue, and process lifetime ordering without pretending
that firmware executed or rasterized the command.

`--submit-only` is intentional: fake G17 does not rasterize pixels. Running the
same binary without that option retains the normal framebuffer pixel check for
VirGL and physical hardware, and therefore reports an image-validation failure
on fake G17 after the otherwise successful submit.

The generated encoder's output buffer has a fixed capacity of 392 writes. The
actual write count remains descriptor- and path-dependent; 392 is not a
required-write invariant for a job.

The fake driver's current descriptor contains manifest-driven recovered scalar
defaults. Every Mesa BO/GPU-VA input now crosses the backend boundary with
explicit provenance and must resolve through FakeG17VM before both encoding and
synthetic completion. Encoder, load/store pipeline, depth, and stencil plane
references now also cross proven native G17 descriptor members. Translating
the remaining references plus the Mesa-command and format/stride values remains
the next software integration step. The resource-correlation recovery tool
narrows that work to descriptor-member candidates copied from observed Apple
resource ranges, but does not label them as Mesa fields. The recovered nine-field Apple
normalized-command copy is likewise not used as an offset shortcut: those
sources are Apple's proprietary payload, not Mesa's UAPI. Native PMP/RTKit
boot, DART/UAT page tables,
completion IRQs, and actual firmware acceptance remain physical-hardware
gates. The fake driver has no import of or route to those hardware facilities.
