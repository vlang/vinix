// SPDX-License-Identifier: GPL-2.0-or-later
import lwjglpatch
import os

fn main() { exit(lwjglpatch.patch_cli(os.args[1..])) }
