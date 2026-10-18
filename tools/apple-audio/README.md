# M1 Air audio evidence

`probe.v` connects using the same SSH destination as `deploy-to-m1.sh`
(`VINIX_M1_REMOTE`, or `sergey@macbook-air-sergej.local`). It reads the J313
audio nodes, loaded driver versions and UUIDs, and downloads the kernel cache
named by the **current** `chosen/boot-objects-path`. It makes no remote changes
and needs no root access. Use a new output directory for each capture.

```sh
v -nocache -cc clang -o /tmp/vinix-audio-probe tools/apple-audio/probe.v
/tmp/vinix-audio-probe --output /tmp/m1-audio-capture
```

Extract the drivers with the repository's V Mach-O/IMG4/LZFSE parser:

```sh
tools/agx-re/extract_fileset --kernel /tmp/m1-audio-capture/kernelcache \
  --output /tmp/m1-audio-kext \
  --entry com.apple.driver.AppleTAS5770LAmp \
  --entry com.apple.driver.AppleMCA2-T8103 \
  --entry com.apple.driver.AudioDMAController-T8103 \
  --entry com.apple.driver.AppleS5L8960XNCO
llvm-objdump --macho --disassemble /tmp/m1-audio-kext/driver.AppleTAS5770LAmp.macho
```

Compare the extracted UUIDs with `loaded.txt` before interpreting code. The
`/System/Library/KernelCollections/BootKernelExtensions.kc` file on this M1 is an
x86_64 placeholder; it does not contain the running ARM drivers.

The first capture and recovered register sequence are documented in
[m1-speakers.md](../../docs/m1-speakers.md). Raw captures and proprietary driver
binaries belong outside version control. This tool observes macOS; it does not
test Vinix playback or write codec registers.
