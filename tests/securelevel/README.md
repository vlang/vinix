# Securelevel userspace device and domain policy

Securelevel 2 prevents writing block-device descriptions, including descriptors
opened before the level was raised. Open, write, pwrite and writev enforce the
same rule. Read-only disk opens and O_PATH remain available; filesystem writes
and cache/metadata writeback call resources directly and remain available.

At securelevel 1, an established initial-UTS domain name cannot be changed or
cleared. Private UTS namespaces may configure their independent names. Raising
the level uses an atomic compare/exchange loop so concurrent raises cannot
accidentally lower a newer policy. Only init may lower a positive level.

Run `python3 tests/securelevel/run.py` for ARM64 or add `--arch=amd64` for x86.
The runner follows the existing dumpability VM setup and environment overrides.
The disk fixture is a block-mode inode used to exercise userspace dispatch;
the ARM runner also mounts a real persistent EXT2 /root and checks ordinary
file writes/fsync at level 2. Hardware-cache barriers have separate storage tests.

This extends SEC3 but does not close it: mounted-disk protection at level 1,
physical-memory devices, and controls for future packet filters remain to be
implemented. Clock backward-step protection at level 2 is tested separately.
