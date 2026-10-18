# Built-in speakers on the M1 MacBook Air

Vinix plays through the two built-in speakers of the base M1 MacBook Air
(J313). They appear as the OSS `/dev/dsp`, the same device QEMU's VirtIO card
provides, so SDL programs play with `SDL_AUDIODRIVER=dsp` and nothing else
changes. Playback is 16-bit stereo at 44.1 or 48 kHz. The headphone jack,
the microphones and every other Mac are not supported.

## The hardware path

Samples go from a ring buffer through ADMAC, the audio DMA controller, into
the MCA I2S block, and out of two I2S ports to a pair of TI TAS5770L
amplifiers, one per speaker. The amplifiers are configured over two of the
P.A. Semi I2C buses. ADMAC reaches memory through the SIO DART, and the MCA
bit clock comes from the NCO clock generator. The register sequences follow
Asahi Linux's drivers (`mca.c`, `apple-admac.c`, `clk-apple-nco.c`,
`tas2770.c`, `i2c-pasemi-core.c` and the `macaudio.c` machine driver).
The two MCA clusters in use sit in power domains that are externally clocked:
they change state only while their clock runs. Each stream powers a cluster up
after its clock starts and down before it stops, in the order `mca.c` uses,
and touches a cluster's registers only while it is powered.

After resetting each amplifier, Vinix also restores J313's Class-D clock
synchronization, brownout threshold/timing and limiter settings, recovered
from Apple's driver on the physical Mac. Every setting is read back while
the amplifier is still shut down; any failed write or mismatch holds the
shared shutdown line low. These settings supplement the thermal model.

The wiring is taken from the device tree the Asahi boot chain passes on: the
`Speakers` link of the `apple,j313-macaudio` sound node names the MCA ports
and the amplifiers, and those lead to the clocks, DMA channels, buses, pins
and power domains. Some J313 boot trees omit the codecs' shared
`shutdown-gpios` property. In that case the driver accepts AP GPIO 181 from
the [Asahi J313 board description](https://github.com/AsahiLinux/linux/blob/asahi/arch/arm64/boot/dts/apple/t8103-j313.dts)
only after checking the exact codec models, I2C addresses and buses, and
current and voltage sense slots. Other missing or conflicting wiring leaves
the speakers off.

- `kernel/apple/speakers/speakers.v`: device tree discovery, power, pins, the
  DART, `/dev/dsp`, and the service thread.
- `kernel/apple/speakers/spkcore/core.v`: the register work, the playback and sense
  rings, and the protection model.

## Speaker protection

Laptop speakers are driven close to what they survive, and the amplifiers do
not protect them. macOS models how hot each voice coil gets and turns the
volume down in time; Asahi Linux does the same with `speakersafetyd`. The
amplifiers report the voltage across and the current through each coil, and
Vinix captures that on a second MCA frontend and runs speakersafetyd's model
in the kernel, with its J313 parameters. It runs whenever the speakers can
make sound, so there is no daemon to forget.

The rules are stricter than Linux's:

- The amplifier gain is fixed at level 10 (16 dBV), the value macOS uses on
  this machine, and it is read back after it is set.
- Each stream starts 20 dB down. The limit lifts, over about a quarter of a second, only once the
  measured voltage has been seen to follow what is being played.
- If no sense data arrives for 250 ms, the output drops back to -20 dB at
  once.
- A speaker that measures no voltage while it should be playing keeps the
  output at -20 dB.
- Time spent playing never counts as cooling time, even across gaps in the
  sense data. Only time with the amplifiers shut down cools the model.
- A modelled temperature past the 120 °C limit plus 15 °C of headroom, or
  sense data that implies negative power, shuts both amplifiers down through
  their shared shutdown line. They stay off until reboot.
- A lost I2C write that should have lowered the volume is treated the same
  way.

## On the machine

The boot log reports what it found:

```
apple-speakers: left amplifier ready (revision 0x...)
apple-speakers: right amplifier ready (revision 0x...)
apple-speakers: MacBook Air J313 speakers on MCA ports 0x3, amplifiers 0x31 and 0x34; output held at -20 dB until the sense data checks out
```

The first loud sound should then print:

```
apple-speakers: sense data tracks the output; protection model in control
```

If that line never appears, the speakers keep working 20 dB down, and the
lines around it say why. A line ending in `speakers off` means the device
tree or the hardware was not as expected. Every path through the driver
prints at least one `apple-speakers:` line, so a boot with none at all ran a
kernel built without the driver; `scripts/deploy-m1-efi.sh --sound-initramfs` and
`--apple-speakers` refuse to install such a kernel.

To turn the driver off, boot with `vinix.apple_speakers=0` on the kernel
command line, or build the kernel with `-d no_apple_speakers`.
The `desktop-basic` deployment mode adds that disable flag. For a desktop
with speakers, use `desktop-sound` or `desktop-drivers`. Replacing a kernel
alone preserves the installed command line, including any disable flag;
check all copies of `limine.conf` on the EFI partition when enabling audio.

## Tests

`tests/apple-speakers/run.sh` compiles the production V core on the host
against a simulated machine: amplifiers behind the I2C FIFOs, ADMAC rings
that move real samples in simulated time, and sense data derived from what
the amplifiers are playing. It checks the register programming, that what is
written is exactly what is played, each protection rule, and that the
fixed-point model matches a double-precision port of speakersafetyd to
within 0.005 °C over 90 seconds.
It also checks the recovered J313 initialization, rejects a failed write to
each of its registers on either amplifier, and detects an acknowledged write
that did not reach the clock synchronization register.

```sh
CC=clang sh tests/apple-speakers/run.sh
```

The macOS reference was collected on the physical M1 Air. Vinix playback
still requires an audible check after booting the updated kernel; the host
model does not prove that the speaker wiring or clocks work on hardware.

## macOS reference, 2026-10-18

SSH to the deployment host reported `MacBookAir10,1`, macOS 26.3.1 (a), build
`25D771280a`, kernel UUID `527D5275-825C-3A45-AA90-5021F6817874`.
`chosen/boot-objects-path` selected the active kernel cache, whose SHA-256 is
`528687f2c5e18a6f991de53b29654eca85bcdd0125aca4e711c03d8718314596`.
The extracted drivers matched the UUIDs reported by `kmutil showloaded`:

| Driver | Version | UUID |
| --- | --- | --- |
| AppleTAS5770LAmp | 930.11 | CDCF8585-2F62-3858-966C-7AA63FA7F3A2 |
| AppleMCA2-T8103 | 1000.4 | 3E3008E9-7688-3F8F-A140-65600EECA8BA |
| AudioDMAController-T8103 | 530.10 | 6DDE9AAE-7C0A-39D4-AC97-98E003DCA656 |
| AppleS5L8960XNCO | 1 | 5E48459C-500B-3105-B42D-9BD6C9D1740F |

The live `audio-tas5770L-spkr-l@31` node contains
`speaker-config=<000a0000010a0000>`,
`bop-config=<820650040000000000000000>` and
`function-reset=<6e0000004f495047b500000001000100>`.
The second amplifier is `audio-tas5770L-spkr-r@34`, reached through `speaker1`.
These confirm the existing gain 10, I2C addresses and shared AP GPIO 181.
The left control node owns the configuration for both amplifiers.

`AppleTAS5770LAmp::ConfigureSpeakers` starts at `0xfffffe0009a93f20`.
Its common setup path and `applyBOPConfig` (`0xfffffe0009a9475c`) write:

| Page 0 register | Value | Evidence |
| --- | --- | --- |
| 0x08 PDM_CFG0 | 0x40 | Common setup, 0xfffffe0009a943b4: Class-D synchronization |
| 0x1c BOP_CFG1 | 0x82 | bop-config byte 0, applyBOPConfig |
| 0x1d BOP_CFG2 | 0x06 | bop-config byte 1, applyBOPConfig |
| 0x16 LIM_CFG1 | 0x50 | bop-config byte 2, applyBOPConfig |
| 0x17 LIM_CFG2 | 0x04 | bop-config byte 3, applyBOPConfig |
| 0x15 LIM_CFG0 | 0x14 | initLIMConfig default when lim-config is absent |
| 0x1b BOP_CFG0 | 0x01 | Common setup, 0xfffffe0009a944fc |

The register meanings are cross-checked against the
[TI TAS2770/TAS5770LC0 data sheet](https://www.ti.com/lit/ds/symlink/tas2770.pdf),
sections 8.5.2.9 and 8.5.2.22–30. Class-D synchronization was previously off;
the brownout threshold and recovery timing were reset defaults rather than
J313's values. Apple's optional page-0xfd buzz/OCP patches are gated by
`enable-buzz-fix` and `maximize-ocp-threshold`; neither property exists on
this Mac, so those patches are not applied. Serial format settings remain
those for Vinix's S16_LE I2S stream and sense capture.

Use the read-only [audio probe](../tools/apple-audio/README.md) to repeat the
capture. The extracted amplifier Mach-O SHA-256 is
`a72d41308319a2cee0c629f24cbf4448b9f8a6ca3a770bf8b4c7c128f024ac13`.
