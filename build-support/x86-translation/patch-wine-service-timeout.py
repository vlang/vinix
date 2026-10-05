#!/usr/bin/env python3
"""Give translated Wine services enough time to reach their control pipe.

Wine 9.17 gives a newly spawned service ten seconds to connect to services.exe.
That is ample for native execution, but an x86 service starting through
qemu-user on Vinix can spend slightly longer loading its PE modules before it
calls StartServiceCtrlDispatcher.  Increase only Wine's default service-pipe
timeout to sixty seconds; the normal ServicesPipeTimeout registry override
continues to take precedence.

The adjacent initialized globals make a version-specific signature shared by
Alpine v3.21's PE32 and PE32+ Wine 9.17 services.exe builds.  Refuse to patch
an unknown binary instead of replacing an unrelated integer constant.
"""

from pathlib import Path
import os
import sys
import tempfile


OLD_GLOBALS = (
    (120_000).to_bytes(4, "little")  # autostart delay
    + (60_000).to_bytes(4, "little")  # service kill timeout
    + (10_000).to_bytes(4, "little")  # service pipe timeout
)
NEW_GLOBALS = (
    (120_000).to_bytes(4, "little")
    + (60_000).to_bytes(4, "little")
    + (60_000).to_bytes(4, "little")
)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} SERVICES.EXE", file=sys.stderr)
        return 2

    target = Path(sys.argv[1])
    data = bytearray(target.read_bytes())
    old_count = data.count(OLD_GLOBALS)
    new_count = data.count(NEW_GLOBALS)
    if (old_count, new_count) == (0, 1):
        print(f"translated-service timeout already extended: {target}")
        return 0
    if (old_count, new_count) != (1, 0):
        raise ValueError(
            "unexpected Wine services timeout globals: "
            f"old={old_count}, new={new_count}"
        )

    offset = data.index(OLD_GLOBALS)
    data[offset : offset + len(OLD_GLOBALS)] = NEW_GLOBALS
    mode = target.stat().st_mode
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
        output.write(data)
        temporary = Path(output.name)
    os.chmod(temporary, mode)
    os.replace(temporary, target)
    print(f"extended translated-service startup timeout: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
