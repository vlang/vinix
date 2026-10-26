# Streaming evidence archive verification

`evidence-archive-check.v` independently reads an external sealed tar.gz without
extracting its payloads. It accepts the historical `bundle.sha256` file/link
inventory used by `software-release-routing-bundle.v`; that sealer and its checker
are unchanged.

```
v -prod -o evidence-archive-check tests/packages/evidence-archive-check.v
evidence-archive-check check ARCHIVE ROOT_BASENAME MANIFEST EXPECTED_ARCHIVE_SHA256
v -prod -o evidence-archive-check-controls tests/packages/evidence-archive-check-controls.v
evidence-archive-check-controls VERIFIER_BINARY NEW_EXTERNAL_DIRECTORY
```

The reader hashes the compressed archive before and after verification, compares
the embedded manifest with the supplied manifest, and hashes every ordinary
member's reconstructed bytes, including sparse holes. Symlinks match literal
targets without following them. Hardlinks must directly name a separately
observed regular payload with the same sealed hash. Duplicate members, path
escapes, unexpected or missing payloads, type changes and special files fail.

Libarchive exposes concatenated tar and AppleDouble members through explicit
checked options. A separate bounded zlib streaming pass checks every gzip
member's CRC, length and complete trailer, including concatenated streams. Read
warnings and errors fail. The C interfaces use explicit integer widths and
zlib's public structure size/version guard.

This manifest authenticates regular-file bytes and literal symlink targets.
Canonical directory headers, including empty directories, are permitted;
directory existence, permissions, owners and timestamps are outside its scope.
External symlink referents must remain separately preserved when required by an
original evidence checker. The reader does not authorize deleting any evidence.

Qualification used the isolated worktree based on
`2213d9505f811799b769213d31f0c8b50e0676d8`, with controls committed in
`3afb4e4f3` and `bdb0b95f0`. Normal and `-prod` builds each passed all 33 explicit
controls: six accepted baselines and 27 refusals with exact exit status 1.
The accepted cases cover sparse reconstructed bytes, forward and backward
hardlinks, literal external/cyclic symlinks, empty directories, concatenated gzip
members, more than 1 MiB of compressed and decoded input, and a gzip member ending
exactly at the 1 MiB compressed-input boundary. Refusals include changed bytes
and seals, missing/extra/duplicate members, AppleDouble and appended hidden
payloads, path escapes, hardlink chains/cycles, special files, truncated gzip and
corrupt CRC/length trailers. These are host builds using the default collector;
there is no sanitizer, manual-free or target-guest qualification claim.

Complete build argv, source/tool/binary hashes, fixtures and invocation logs are
preserved outside Git under
`/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a`:

| Receipt | SHA-256 |
| --- | --- |
| `archive-controls-build-03/builds.json` | `69afa6d1254eb4b0f1b6ec06c73dbfa91fbf8fbdecaf3fb6bc25d080152b4b85` |
| `archive-controls-normal-03/results.json` | `639601d07f784c5db470913d7f434c034e784e987c290aef022601aefa35064b` |
| `archive-controls-prod-04/results.json` | `65973b6751cef1ef256eab25d7e0b7c2cfc759f079afb9e02da682d27c515de3` |

The reader source hash is
`59e10b89aa8416207bfaad35446b8dd389d64425c61585dca7328ce15c88ebfa`;
the controls source hash is
`1670f2705d50f747c1e25e4df2b6b96895e67c07af3c55fc1a70787ebb88b7ad`.
Actual builds used `/Users/alex/code/v/v`
(`1192282d8f676924c3fbd33d0c1a85ae37df3e7294610a35db253b966e34da6c`)
and `/opt/homebrew/opt/llvm/bin/clang`
(`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`).
The production reader binary hash is
`8808f2000e0ed1f9977a2ed9bd42ef0eaf0a4143be3440222a38be3237d1757a`.

The complete qualification capsule is
`evidence-archive-verifier-qualification-01.tar.gz` in that external directory:
archive SHA-256
`018b98014c0e909840dec5e04074bba6f4f840ee5cea46fafeea734717f22450`,
manifest SHA-256
`86d7c985bc4f60e54f085b840d64508f1d1f503a588485e3e3a086bab9d50ffb`.
It includes all four actual builds, complete control inputs/logs, exact sources,
and build/copy/sealing helpers. The unchanged sealer checked its source inventory
around archiving; the qualified production reader independently accepted all
311 sealed files, one gzip member and 18,125,312 decoded bytes without extraction.
The sibling `evidence-archive-verifier-qualification-01-verification.json`
receipt has SHA-256
`ce5f432f29b3ea5afe2c3274dab44d35342e54a55b25935214e84feb41fe8b7b`.
An independent reviewer also rehashed every final control input, argv and log,
the selected binaries and both exact 33-case result matrices.
