#!/usr/bin/env python3
"""Create a disposable ui2 module overlay for Vinix headless builds.

The overlay keeps the upstream checkout untouched. It links all upstream
sources into a generated module tree and adds Vinix's tiny Linux-headless
`bounds()` bridge, which compile-time `$vml` builders require.

    stage_ui2.py <output-ui2-dir> <source-ui2-dir> <bridge.v>
"""

import os
import re
import shutil
import sys


def symlink_entries(source, destination):
    os.makedirs(destination, exist_ok=True)
    for name in sorted(os.listdir(source)):
        os.symlink(os.path.abspath(os.path.join(source, name)),
                   os.path.join(destination, name))


def module_subdirs(manifest):
    with open(manifest) as handle:
        text = handle.read()
    match = re.search(r"\bsubdirs\s*:\s*\[([^]]*)\]", text, re.DOTALL)
    if not match:
        return []
    return re.findall(r"['\"]([^'\"]+)['\"]", match.group(1))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__.strip().splitlines()[-1].strip())
    output, source, bridge = map(os.path.abspath, sys.argv[1:])
    manifest = os.path.join(source, "v.mod")
    if not os.path.isfile(manifest):
        sys.exit("%s: ui2 v.mod not found" % source)
    if os.path.isdir(output):
        shutil.rmtree(output)
    os.makedirs(output)
    shutil.copyfile(manifest, os.path.join(output, "v.mod"))

    # Root-level resources remain available to @VMODROOT paths. V sources live
    # in v.mod's same-module subdirectories; ui/ is expanded so the bridge can
    # sit beside its upstream peers without modifying the checkout.
    assets = os.path.join(source, "assets")
    if os.path.exists(assets):
        os.symlink(assets, os.path.join(output, "assets"))
    for subdir in module_subdirs(manifest):
        upstream = os.path.join(source, subdir)
        staged = os.path.join(output, subdir)
        if subdir == "ui":
            symlink_entries(upstream, staged)
            shutil.copyfile(bridge, os.path.join(staged, "vinix_headless_bounds.v"))
        else:
            os.symlink(upstream, staged)


if __name__ == "__main__":
    main()
