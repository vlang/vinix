// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn main() {
	match os.args[1] {
		'replace' {
			os.cp(os.executable(), os.args[2])!
			os.chmod(os.args[2], 0o755)!
		}
		'disable' { os.chmod(os.args[2], 0o600)! }
		'invoke' { os.execvp(os.args[2], ['write', os.args[3]])! }
		'write' { os.write_file(os.args[2], 'unexpected tool ran')! }
		else { exit(2) }
	}
}
