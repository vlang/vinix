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

Everything is taken from the device tree the Asahi boot chain passes on: the
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
- `kernel/c/apple_speakers.c`: the register work, the playback and sense
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
kernel built without the driver; `deploy-m1-efi.sh --sound-initramfs` and
`--apple-speakers` refuse to install such a kernel.

To turn the driver off, boot with `vinix.apple_speakers=0` on the kernel
command line, or build the kernel with `-d no_apple_speakers`.

## Tests

`tests/apple-speakers/run.sh` compiles the production C file on the host
against a simulated machine: amplifiers behind the I2C FIFOs, ADMAC rings
that move real samples in simulated time, and sense data derived from what
the amplifiers are playing. It checks the register programming, that what is
written is exactly what is played, each protection rule, and that the
fixed-point model matches a double-precision port of speakersafetyd to
within 0.005 °C over 90 seconds.

```sh
CC=clang sh tests/apple-speakers/run.sh
```

None of this has been checked on the machine itself yet.
