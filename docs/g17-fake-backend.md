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

`gpu.verify_fake_g17` is the V adapter. `gpu.submit_fake_g17` first installs a
normal `WorkItem` in the shared `WorkQueue`, verifies the encoded command, and
then injects either a successful completion or a channel-error completion.
That signals the same `DmaFence` objects and exercises the same queue teardown
bookkeeping as a hardware completion.

## Run the host test

The host test compiles the exact allocation-free C verifier linked into the
kernel. It covers successful traces, every validation class, and a 314-entry
stress trace:

```sh
./tests/agx-fake-g17/run.sh
SANITIZE=1 ./tests/agx-fake-g17/run.sh
```

Compile the kernel-side V adapter as part of the normal AArch64 build:

```sh
make -C kernel ARCH=aarch64
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

## Remaining path to a Mesa triangle

The Mesa submit ioctl remains fail-closed for G17 today. The host reference
encoder now proves that the recovered 3D graph can produce a path-exact command
accepted by the fake verifier plan compiler. The next integration step is an
allocation-free kernel form of the same state machine and routing G17 queues to
`submit_fake_g17` when a test-only backend is selected. Only after that can a
VM Mesa triangle exercise the full native G17 software path. Native PMP/RTKit
boot and actual firmware acceptance remain hardware-only gates.
