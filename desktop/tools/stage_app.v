// SPDX-License-Identifier: GPL-2.0-only
module main
import os
import stagehost
fn main() {
	if os.args.len == 3 && os.args[1] == '--install-controller' { os.cp(os.executable(), os.args[2]) or { eprintln(err); exit(1) }; os.chmod(os.args[2], 0o700) or { eprintln(err); exit(1) }; return }
	if os.args[1..] == ['--help'] { println('stage_app <staging-dir> <desktop-dir> <example-dir>...'); return }
	stagehost.app_main(os.args[1..]) or { eprintln(err); exit(1) }
}
