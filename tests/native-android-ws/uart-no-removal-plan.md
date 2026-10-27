# Empty-removal diagnostic plans

`uart-no-removal-plan.v` writes a version-2 input plan for the unchanged
`diagnostic-uart-reconstruct.v`. It accepts one exact, immutable UART interval
from [uart-snapshot.md](uart-snapshot.md), pinned by its SHA-256:

```sh
uart-no-removal-plan --service-query /absolute/interval.log INTERVAL_SHA256 /absolute/fresh-plan.json
diagnostic-uart-reconstruct /absolute/interval.log /absolute/fresh-plan.json /absolute/fresh-diagnostic
```

Use `--maps-account` for the Maps account prefix. Inputs must be canonical,
single-link regular files with mode 0400, bounded to 8 MiB. Outputs are fresh,
exclusive mode-0400 files outside a checkout. The writer requires exactly one
selected BEGIN/END pair, matching digest/size/count metadata, ordered four-field
CHUNK records, bounded lengths, LF/CRLF boundaries and canonical decimals.
Foreign, embedded, duplicate and incomplete exports fail. Plans always contain
`removals: []`.

The writer does not decode, remove or repair payload bytes. The unchanged
diagnostic reconstructor separately validates base64, archive length/hash and
all archive entries. Creating a plan is not a successful import or a guest
runtime result. Retain original intervals, plans and failures unchanged.

The host binary is
`/Users/alex/.local/state/vinix/android/uart-no-removal-plan-2026-10-27-r4/uart-no-removal-plan`,
SHA-256 `4fc5df1b2d704f94a027db7cf80dac7f097e1799b49166685399696f32b494af`.
Its retained source SHA-256 is
`264645e1a38332898973f20f41eee4288f9dede6a20d4a234cf753096a02ec46`.
The adjacent source and selftest outputs remain in that external bundle;
guarded compile/selftest receipts and logs share its prefix outside Git.

The pinned V compiler built it in 0.40 seconds with 182,026,240 B maximum
resident memory, 182,583,296 B peak sampled aggregate RSS and zero swaps under
a 600 MiB process-tree cap, 300 seconds, 1 GiB disk reserve and 512 MiB shared
growth limit. Selftests passed malformed, repeated, foreign and incomplete
exports, decimal/order/count errors, input-pin mismatch, existing output and
symlink/FIFO refusal and missing-LF, CR-only and repeated-CR boundaries. The
executable selftest took 0.22 seconds, 3,293,184 B maximum RSS and zero swaps.
Independent review led to nonblocking input opens and exact line-boundary
checks. Earlier candidates and one C-declaration compile failure remain
preserved in sibling `-r1`, `-r2` and `-r3` bundles. Host tooling checks do not
establish ART or Maps behavior.
