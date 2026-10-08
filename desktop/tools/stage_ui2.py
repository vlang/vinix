#!/usr/bin/env python3
"""Create a disposable ui2 module overlay for Vinix headless builds.

The overlay keeps the upstream checkout untouched. It links the portable and
Vinix-relevant sources into a generated module tree and adds Vinix's tiny
Linux-headless `bounds()` bridge, which compile-time `$vml` builders require.

    stage_ui2.py <output-ui2-dir> <source-ui2-dir> <bridge.v>
"""
import os
import re
import sys
from _stage_native import call, _untext

EXCLUDED_SUBDIRS = {"appkit"}
def staged_source(name, source_path):
    return call("staged_source", name, os.fspath(source_path))

def symlink_entries(source, destination):
    return call("symlink_entries", os.fspath(source), os.fspath(destination))

def module_subdirs(text):
    return [_untext(value) for value in call("module_subdirs", text)]

def filter_manifest_subdirs(text):
    return call("filter_manifest_subdirs", text)

def main():
    return call("ui_main", *sys.argv[1:])


if __name__ == "__main__":
    main()
