module main

import os
import runtimefixture

fn main() {
	if os.args.len == 3 && os.args[1] == '--child-boot' {
		runtimefixture.run_boot(os.args[2]) or { panic(err) }
		return
	}
	if os.args.len == 3 && os.args[1] == '--child-runtime' {
		runtimefixture.run(os.args[2]) or { panic(err) }
		return
	}
	if os.args.len == 3 && os.args[1] == '--child-musl' {
		runtimefixture.run_musl(os.args[2]) or { panic(err) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--original-source' {
		println(runtimefixture.source_identity())
		return
	}
	if os.args.len == 3 && os.args[1] == '--install-fixture' {
		os.cp(os.executable(), os.args[2]) or { panic(err) }
		os.chmod(os.args[2], 0o700) or { panic(err) }
		return
	}
	runtimefixture.run_guarded(if os.args.len > 1 { os.args[1] } else { '' }) or { panic(err) }
}
