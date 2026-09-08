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
- encoded values under an explicit 64-bit mask; and
- address-valued entries against live GPU-VA ranges and alignment.

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

At the Vinix prompt, select lifecycle-only validation:

```sh
/usr/bin/run-gl-triangle-agx --submit-only
```

The same check can be run non-interactively from the host after building the
AArch64 kernel:

```sh
python3 tests/agx-fake-g17/run_vm.py
```

The runner creates scratch disk/NVRAM files by default, waits for the guest
shell, checks the exact Mesa renderer and render/fence completion messages,
and exits QEMU. Set `VINIX_BOOT_DISK` to reuse an existing test image or
`VINIX_FAKE_G17_VM_TIMEOUT` to change its 180-second deadline.

Mesa should identify the renderer as `Apple M5 Max (G17C C0)` and report that
the render submit and fence completed successfully. The first kernel message
also includes the staged Mesa fragment command ID and framebuffer dimensions.
This exercises the Asahi DRM ioctl layout, shared render/compute command
normalization, immutable attachment staging, per-file GEM and VM ownership,
mappings, contexts, queues, sync objects, the generated G17 encoder, the
independent verifier, synthetic completion, fence waiting, and process
teardown.

`--submit-only` is intentional: fake G17 does not rasterize pixels. Running the
same binary without that option retains the normal framebuffer pixel check for
VirGL and physical hardware, and therefore reports an image-validation failure
on fake G17 after the otherwise successful submit.

The generated encoder's output buffer has a fixed capacity of 392 writes. The
actual write count remains descriptor- and path-dependent; 392 is not a
required-write invariant for a job.

The fake driver's current descriptor contains deterministic recovered scalar
defaults. The complete, validated Mesa render command is now available at the
backend boundary, but translating its semantic fields into native G17
descriptor members remains the next software integration step. The recovered
nine-field Apple normalized-command copy is not used as an offset shortcut:
that source is Apple's proprietary payload, not Mesa's UAPI. Native PMP/RTKit
boot, DART/UAT page tables, completion IRQs, and actual firmware acceptance
remain physical-hardware gates. The fake driver has no import of or route to
those hardware facilities.
