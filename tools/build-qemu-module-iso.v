// SPDX-License-Identifier: GPL-2.0-only
import archivehost
import os
fn main() { archivehost.run('iso', os.args[1..]) }
