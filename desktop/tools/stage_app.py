#!/usr/bin/env python3
"""Stage the desktop's sources plus a ui2 example into one directory to build.

The desktop hosts ui2 applications in its windows, and an application's model
is V code that has to be compiled in. Rather than copy an example into the
repository and let the copy drift, the build takes the example's own source
straight from the ui2 checkout and compiles it alongside the desktop.

Only one thing is removed: the example's `fn main()`. It exists to open a
platform window and block, which is precisely the job the desktop is doing
instead. Everything the application actually is — its model, its methods, its
QML document — is compiled unmodified, so what runs on Vinix is the example
and not a retelling of it.

Both are `module main`, so they can share a directory. The desktop's own files
are symlinked rather than copied, so editing one is picked up by the next
build.

    stage_app.py <staging-dir> <desktop-dir> <example-dir>...
"""

import os
import re
import shutil
import sys

# The example's entry point, and everything after it. Every ui2 example ends
# with `fn main()`, so cutting from there to the end of the file takes the
# whole function without having to match braces.
MAIN_PATTERN = re.compile(r"^fn main\(\) \{", re.MULTILINE)


def stage_desktop(staging, desktop_dir):
    for name in sorted(os.listdir(desktop_dir)):
        source = os.path.join(desktop_dir, name)
        if not os.path.isfile(source):
            continue
        if not (name.endswith(".v") or name.endswith(".h")):
            continue
        link = os.path.join(staging, name)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink(os.path.abspath(source), link)


def strip_main(text, origin):
    match = MAIN_PATTERN.search(text)
    if not match:
        sys.exit("%s: no `fn main()` to remove; is this a ui2 example?" % origin)
    if MAIN_PATTERN.search(text, match.end()):
        sys.exit("%s: more than one `fn main()`" % origin)
    trailing = text[match.end():]
    if "\nfn " in trailing or "\npub fn " in trailing:
        sys.exit("%s: `fn main()` is not the last function; cannot cut to end"
                 % origin)
    header = (
        "// Staged from %s by desktop/tools/stage_app.py.\n"
        "// The example's `fn main()` is removed — it opens a platform window\n"
        "// and blocks, which is the job the desktop is doing instead. The rest\n"
        "// is the example's own source, unmodified.\n" % origin
    )
    body = text[:match.start()].rstrip() + "\n"
    # `run_qml` was often the file's only use of ui2, and V rejects an import
    # nothing references.
    if "ui2." not in body:
        body = body.replace("\nimport ui2\n", "\nimport ui2 as _\n", 1)
    return header + body


def stage_example(staging, example_dir):
    name = os.path.basename(os.path.normpath(example_dir))
    main_path = os.path.join(example_dir, "main.v")
    if not os.path.isfile(main_path):
        sys.exit("%s: no main.v" % example_dir)

    with open(main_path) as handle:
        text = handle.read()
    origin = os.path.join("third_party/ui2/examples", name, "main.v")
    with open(os.path.join(staging, "app_%s.v" % name), "w") as handle:
        handle.write(strip_main(text, origin))

    # Assets the example embeds sit beside its source, and $embed_file
    # resolves them relative to the file that names them.
    for asset in sorted(os.listdir(example_dir)):
        if asset.endswith(".v"):
            continue
        source = os.path.join(example_dir, asset)
        if os.path.isfile(source):
            shutil.copyfile(source, os.path.join(staging, asset))


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__.strip().splitlines()[-1].strip())
    staging, desktop_dir = sys.argv[1], sys.argv[2]
    examples = sys.argv[3:]

    if os.path.isdir(staging):
        shutil.rmtree(staging)
    os.makedirs(staging)

    stage_desktop(staging, desktop_dir)
    for example in examples:
        stage_example(staging, example)
    print("    staged %d example(s) into %s" % (len(examples), staging))


if __name__ == "__main__":
    main()
