// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import utilitysource
fn main() {
	args := os.args[1..]
	if args.len == 2 && args[0] == 'materialize' {
		utilitysource.materialize(args[1]) or { eprintln(err); exit(1) }
	} else if args.len == 3 && args[0] == 'merge' {
		utilitysource.merge(args[1], args[2], utilitysource.tests) or { eprintln(err); exit(1) }
	} else if args.len == 3 && args[0] == 'merge-parity' {
		utilitysource.merge(args[1], args[2], utilitysource.parity_tests) or { eprintln(err); exit(1) }
	} else if args.len == 3 && args[0] == 'merge-activity' {
		paths := utilitysource.activity_paths(args[1]) or { eprintln(err); exit(1) }
		utilitysource.merge_paths(paths, args[2]) or { eprintln(err); exit(1) }
	} else { eprintln('native-utility-source materialize DIR | merge|merge-parity|merge-activity ROOT DESTINATION'); exit(2) }
}
