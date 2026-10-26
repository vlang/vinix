The maintained V producer and build driver preserve the complete historical
`wine-source-2026-10-26` bundle under
`/Users/alex/Library/Caches/vinix-codex/section14`. The implementation starts
from Wine worktree revision `b9e739333ee5bc7c2d34db36ebd3c240adc4031b`;
the selected source hashes and literal build environments are retained in
`wine-source-retention-bootstrap-08` and
`wine-source-archive-retention-tools-07/build.json` (SHA256
`e84ff6e5c17170f441ee519ec77d97c5bec6be3d8bb1842facdef21cd82226a5`).
The selected compiler/source/Clang/os binding does not establish a complete
imported-library, header, sysroot or linker closure.

The first full archive remains unchanged at
`wine-source-2026-10-26.tar.gz`, SHA256
`3bb708ac3497c871afde2446bd3b1390908009c5cc34991f5fcba917e618c609`.
The unchanged strict reader refused it. The separate read-only boundary
diagnostic validated its gzip CRC/length and found the first member ends at
byte 986273967, followed by 1873 zero bytes. Its receipt is
`wine-source-gzip-boundary-01/result.json`, SHA256
`ad8d849653a85caf08fa81471d505cc5e6f09582d88eb4ac504c583e8e36eab9`.
The failed producer and all original receipts remain in
`wine-source-archive-retention-01`; the reader has not been relaxed.

Actual stdout controls pass: default bsdtar output had 9810 trailing zero
bytes; `-b 1` had 82. Both raw streams were refused, while distinct APFS
clones trimmed at the validated member boundary passed the unchanged reader.
The named-file baseline also passed. All three accepted tiny archives had
one regular payload, one directory, one gzip member and 6656 decoded bytes.
The receipt pins the fixture, manifest, raw archives and trimmed derivatives:
`wine-source-archive-retention-01-stdout-controls-01/controls.json`, SHA256
`d836c31da1dccc46eff847e2032c7607dc5e00661cfd3d1e0260cd6f7eaa2d5d`.
The unchanged original checker passed before and after these controls with
identical output. Failed tools05/06 compiler attempts are preserved.

The exact tools07 clone continuation exited 1 before creating a derivative
or retention02: its historical inode inventory no longer matches. The root
inode is unchanged, but its modification/change times differ; `SHA256SUMS`
changed inode 370949865 to 373427967 and allocation 3736 to 1520 blocks. Its
current flag 32 denotes filesystem compression. The fresh original checker
still passes all 12,305 sealed files and five objects with the same manifest;
this does not establish unchanged inodes. The refusal, exit and selected
metadata are retained in `wine-source-retention-bootstrap-08/clone-refusal.json`
(SHA256 `486185bd0e86e49a1deaf4937df6dff4fa00416173c589523bcf62f369d008ad`)
and adjacent logs. No clone retry, readmission or reclamation occurred.

Historical reruns require restoring the complete archived `original/`
contents at the original absolute root, retaining the original tools and
external aliases; the wrapper manifest is not part of that original root.
This evidence does not qualify Wine execution or detached-server lease
coverage. The producer assumes stopped trusted writers and does not provide
a hostile concurrent-pathname guarantee.
