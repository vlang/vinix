// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main
import os
import packageserver
fn main() {
	if os.args.len == 3 && os.args[1] == '--install-server' { os.cp(os.executable(), os.args[2]) or { eprintln(err); exit(1) }; os.chmod(os.args[2], 0o700) or { eprintln(err); exit(1) }; return }
	exit(packageserver.cli(os.args[1..]))
}
