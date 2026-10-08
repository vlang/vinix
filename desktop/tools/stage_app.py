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

The desktop's translations, desktop/translations/*.tr, are compiled in as
translations_data.v. Every build mode then carries them: `$embed_file` only
embeds under -prod, and the development builds Vinix runs on itself would
otherwise read the files from wherever their sources were when the desktop
next starts.

The same applies to icon artwork. app_icon_data.h contains the canonical QOI
bytes as static C arrays, so every compiled desktop can recover a missing or
corrupt installed icon without reading files from its source directory.

    stage_app.py <staging-dir> <desktop-dir> <example-dir>...
"""
import os
import re
import sys
from _stage_native import call, _untext

_patterns = call("patterns")
MAIN_PATTERN = re.compile(_untext(_patterns["main"]), re.MULTILINE)
EMBEDDED_VIEW_PATTERN = re.compile(_untext(_patterns["embedded"]), re.MULTILINE)
LEGACY_LICENSE_PREAMBLE = re.compile(_untext(_patterns["legacy"]))
TRANSLATIONS_DIR = "translations"
TRANSLATIONS_SOURCE = "translations_data.v"
ICON_DATA_HEADER = "app_icon_data.h"

def native_v3_source(text):
    return call("native_v3_source", text)

def v_string(text):
    return call("v_string", text)

def strip_main(text, origin):
    return call("strip_main", text, origin)

def stage_desktop(staging, desktop_dir):
    return call("stage_desktop", os.fspath(staging), os.fspath(desktop_dir))

def stage_translations(staging, desktop_dir):
    return call("stage_translations", os.fspath(staging), os.fspath(desktop_dir))

def stage_icon_data(staging, desktop_dir):
    return call("stage_icon_data", os.fspath(staging), os.fspath(desktop_dir))

def stage_example(staging, example_dir):
    return call("stage_example", os.fspath(staging), os.fspath(example_dir))

def main():
    return call("app_main", *sys.argv[1:])


if __name__ == "__main__":
    main()
