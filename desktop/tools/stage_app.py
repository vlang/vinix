#!/usr/bin/env python3
"""Stage the desktop's sources plus a ui2 example into one directory to build.

The desktop hosts ui2 applications in its windows, and an application's model
is V code that has to be compiled in. Rather than copy an example into the
repository and let the copy drift, the build takes the example's own source
straight from the ui2 checkout and compiles it alongside the desktop.

The example's `fn main()` is removed because opening and blocking a platform
window is the desktop's job. An embedded VML source constant used only by that
entry point is removed with it. The model and its methods remain unmodified, so
a hosted view can bind that model without copying its business logic.

Both are `module main`, so they can share a directory. The desktop's own files
are normally symlinked rather than copied, so editing one is picked up by the
next build. A source with the redundant legacy license preamble is materialized
without that preamble for compatibility with the native V3 compiler.

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
EMBEDDED_VIEW_PATTERN = re.compile(
    r"^const\s+([A-Za-z_]\w*_(?:qml|vml)_source)\s*=\s*"
    r"\$embed_file\([^\n]+\)\.to_string\(\)\n",
    re.MULTILINE,
)
LEGACY_LICENSE_PREAMBLE = re.compile(
    r"\A// Copyright \(c\) [^\n]+\. All rights reserved\.\n"
    r"// Use of this source code is governed by a GPL v2 license\n"
    r"// that can be found in the LICENSE file\.\n\n"
    r"(?=// SPDX-License-Identifier:)",
)


def native_v3_source(text):
    """Remove a redundant pre-SPDX comment that corrupts V3 source offsets.

    The native V 0.5.2 `$vml` lowering currently misattributes tokens later in
    a file when this exact multi-line preamble precedes the existing SPDX
    header. The SPDX header and its copyright remain in the staged source, so
    this compile-only normalization changes no code or licensing information.
    """
    return LEGACY_LICENSE_PREAMBLE.sub("", text, count=1)


def stage_desktop(staging, desktop_dir):
    for name in sorted(os.listdir(desktop_dir)):
        source = os.path.join(desktop_dir, name)
        if not os.path.isfile(source):
            continue
        if not (name.endswith(".v") or name.endswith(".h") or name.endswith(".vml")):
            continue
        destination = os.path.join(staging, name)
        if os.path.lexists(destination):
            os.remove(destination)
        if name.endswith(".v"):
            with open(source) as handle:
                text = handle.read()
            compatible = native_v3_source(text)
            if compatible != text:
                with open(destination, "w") as handle:
                    handle.write(compatible)
                continue
        os.symlink(os.path.abspath(source), destination)


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
    # Runtime examples embed their document so `run_vml` can parse it. A
    # compile-time `$vml` host neither calls that entry point nor needs to ship
    # the source text and embedding support in every utility process.
    for declaration in reversed(list(EMBEDDED_VIEW_PATTERN.finditer(body))):
        name = declaration.group(1)
        if len(re.findall(r"\b%s\b" % re.escape(name), body)) == 1:
            body = body[:declaration.start()] + body[declaration.end():]
    # `run_vml` was often the file's only use of ui2, and V rejects an import
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
