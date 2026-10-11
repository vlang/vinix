// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main
import dictionaryfixture
fn main() { dictionaryfixture.run() or { eprintln(err); exit(1) } }
