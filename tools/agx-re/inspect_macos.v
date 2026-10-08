module main

import macinspect
import os

fn main() {
	result := macinspect.cli(os.args[1..]) or {
		if err.code() == 102 {
			eprintln('inspect_macos: error: ${err}')
			exit(2)
		}
		eprintln('inspect_macos: ${err}')
		exit(1)
	}
	println(result)
}
