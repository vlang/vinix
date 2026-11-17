# DRM syncobj WAIT request framing

Vinix accepts 32-byte binary WAIT (`0xC3`) and 40-byte timeline WAIT (`0xCA`)
requests from before the `deadline_nsec` field. The current 40- and 48-byte
layouts accept the deadline field. Omitted bytes are zeroed in kernel storage,
and output copying stays within the size encoded by the caller.
[Packaged UAPI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h)

Both registrations use the existing extensible decoder. It intersects the two
direction masks, preserves trailing bytes on read/write requests, zeroes them
on read-only requests and gives output-copy faults precedence over handler
errors. The existing buffer owner frees extended heap requests on all exits.
[Packaged DRM dispatcher](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916)

The ASan/UBSan wire fixture executes production registration, decoding, buffer
allocation and user-copy control flow. It uses a handler stub with the production
UAPI structs to observe the deadline and write `first_signaled`. The baseline
at `7f4e1a60c` fails at the historical binary WAIT assertion. The fixed build
passes both historical request sizes, both current sizes, all four directions,
extended tails, buffer exhaustion and copy failures. The syncobj suite exercises
the production wait handlers separately. The AGX file-close suite also passes.

The AArch64 MP and x86_64 kernel builds and all 82 V contract tests pass.
The compiler reports 377 AArch64 and 289 x86_64 allocation sites, with the
same per-file counts and 178 allowance failures as the verified baseline.
Generated C shows a value-only layout copy with no allocator calls.

This increment covers request framing against Omarchy's packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Open items include WAIT deadline
propagation, generic timeline capability reporting, full scheduler behavior
and validation with the matched Mesa stack. All checks ran on the host.

The isolated Vinix `7f4e1a60c` source, tested patch, reference files, binaries,
logs and verified archive restoration are retained under
`/Users/alex/.local/state/vinix/omarchy-m1-wait-wire-20261117/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `7cecd054d09bbf63aeaafbc9d636e10462943482ac02f44245d3dd815427cbbb` |
| `bundle.tar.gz.inventory.txt` | `ca0b9202c63e8009dcd43303b13dab2136b418c73fa7237de4fb6346e1c676ff` |
