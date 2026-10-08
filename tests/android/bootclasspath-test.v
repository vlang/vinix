module main

import os
import runtimefixture

fn main() {
	if os.args.len == 3 && os.args[1] == '--child-boot' {
		runtimefixture.run_boot(os.args[2]) or { panic(err) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--original-source' {
		println(runtimefixture.boot_source_identity())
		return
	}
	runtimefixture.run_boot_guarded(if os.args.len > 1 { os.args[1] } else { '' }) or { panic(err) }
}
