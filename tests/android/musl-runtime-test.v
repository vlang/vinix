module main

import os
import runtimefixture

fn main() {
	if os.args.len == 3 && os.args[1] == '--child-musl' {
		runtimefixture.run_musl(os.args[2]) or { panic(err) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--original-source' {
		println(runtimefixture.musl_source_identity())
		return
	}
	runtimefixture.run_musl_guarded(if os.args.len > 1 { os.args[1] } else { '' }) or { panic(err) }
}
