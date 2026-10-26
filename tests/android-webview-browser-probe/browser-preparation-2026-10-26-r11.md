# Browser diagnostic preparation — 2026-10-26 r11

The r11 preparation includes the preconstructed GTK/WebKit settings fix
`a118cd965` and pinned libproxy runtime closure `577a2d8c2`. It retains source
base revision `b12359ea77841e482677ede71d5ad231f5985ff3` and exact source hashes
in `build.json`. This is build evidence; guest browser execution and Google
authentication require their separate receipts.

The complete bundle is retained at
`/Users/alex/.local/state/vinix/android/browser-probe-build-2026-10-26-r11`.
Its `build.json` SHA-256 is
`083bbcd1dee90bad2f63630b8daf98bf524cfe447c98fbd45467229b56b25391`.
It contains 15 addon packages, 5,568,334 compressed addon bytes and 401 payload
files. The optional known-fault fixture is retained and pinned in full.

| Executable | SHA-256 |
| --- | --- |
| `bin/browser-probe` | `fbdfdb01d4079e9f351f298c358030423513e633e067fb56744213716125bd46` |
| `bin/browser-session` | `bbed8740dbe9ba2afb64b791aec4e4de272e95b04ac7d5f7ee8d4da2842c3fcb` |
| `bin/browser-guest` | `c96e91b90f45c6fe1511618f6e68fbbe810a6ec9a0e3fd82abba35ea9b5a5a3b` |

All three cross-compiles completed. Preparation self-tests passed dependency,
path, payload mode, symlink and fault-fixture tamper cases. The compiler pin is
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`;
the base runtime manifest pin is
`0321ddd8829dbd59ccb713ad2ada0074708b68820929fdc9546ecdd0704b2617`.

The complete prepared tree also has a separate manifest at
`/Users/alex/.local/state/vinix/android/browser-probe-build-2026-10-26-r11-sha256.json`,
SHA-256 `f081256fbfb7c1b35a3629f20173dae0b90130335835fbcf448569d9dc60690f`.
The maintained `inventory.v` records each child directory/file mode, regular
file content hash and symlink target without following links. It keeps its
manifest outside the bundle. Its self-tests detect file content, mode and
symlink changes; a fresh `--check` of the complete prepared tree passed.
