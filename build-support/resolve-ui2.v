module main

import os
import ui2source

fn main() {
	if os.args.len != 2 {
		eprintln('usage: resolve-ui2.v REPOSITORY_ROOT')
		exit(2)
	}
	path := ui2source.resolve(os.args[1], os.getenv('VINIX_UI2_SOURCE')) or {
		eprintln(err.msg())
		exit(1)
	}
	println(path)
}
