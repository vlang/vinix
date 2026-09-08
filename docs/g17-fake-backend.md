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

## Remaining path to a Mesa triangle

The Mesa submit ioctl remains fail-closed for G17 today because Vinix does not
yet emit the recovered HAL300 graph. The next integration step is to port the
3D encoder, compare its output with the independently compiled plan, and route
G17 queues to `submit_fake_g17` when a test-only backend is selected. Only
after that can a VM Mesa triangle exercise the full native G17 software path.
Native PMP/RTKit boot and actual firmware acceptance remain hardware-only
gates.
