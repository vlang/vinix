// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

fn reference_checks() {
	unsafe {
		marker := C.open(c'/home/developer/reference-build.json', C.O_RDONLY)
		if marker < 0 { return }
		check(C.close(marker) == 0, 380)
		jit := C.open(c'/home/developer/reference-jit', C.O_RDONLY)
		if jit >= 0 {
			check(C.close(jit) == 0, 385)
			check(C.mount(c'none', c'/opt/reference/share/jdk', nil, usize(C.MS_REMOUNT | C.MS_BIND), c'wxallowed') == -1
				&& *C.__errno_location() == C.EPERM, 386)
			check(C.open(c'/opt/reference/share/jdk/release', C.O_WRONLY) == -1
				&& (*C.__errno_location() == C.EACCES || *C.__errno_location() == C.EROFS), 387)
		}
		private_receipt(c'/home/developer/reference-build.json', c'/opt/reference')
		ci_fd := C.open(c'/home/developer/ci-jobs.json', C.O_RDONLY)
		ci := ci_fd >= 0
		if ci {
			check(C.close(ci_fd) == 0, 417)
			check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/ci-jobs.json', c'/home/developer/ci-state') == 0, 418)
		}
		outputs := if ci { [&char(c'/home/developer/ci-1'), &char(c'/home/developer/ci-2')]! }
			else { [&char(c'/home/developer/reference-a'), &char(c'/home/developer/reference-b')]! }
		for output in outputs {
			status := if ci { command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/ci-state', nil) }
				else { command(c'/usr/bin/vinix-build', c'build', c'/home/developer/reference-build.json', output) }
			if ci && status != 0 { private_receipt(c'/home/developer/ci-state/state.json', c'ci') }
			mut st := C.stat{}
			check(C.stat(output, &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o700, 383)
			mut path := [512]char{}
			for name in [&char(c'cc'), &char(c'make'), &char(c'ninja'), &char(c'cmake'), &char(c'sqlite3'), &char(c'node'), &char(c'go'), &char(c'java'), &char(c'javac'), &char(c'jar'), &char(c'busybox')]! {
				C.snprintf(&path[0], path.len, c'%s/version-%s.log', output, name)
				emit_command_log(&path[0])
			}
			// Server diagnostics can contain credentials on a failed request.
			// Keep them inside the private output; emit only qualifier verdicts.
			C.snprintf(&path[0], path.len, c'%s/qualify.log', output)
			emit_command_log(&path[0])
			for index in 0 .. 6 {
				C.snprintf(&path[0], path.len, c'%s/work/qualification/java/command-%d.log', output, index)
				emit_command_log(&path[0])
			}
			C.snprintf(&path[0], path.len, c'%s/receipt.json', output)
			emit_receipt(&path[0], c'Vinix', false)
			if status != 0 {
				for name in [&char(c'make'), &char(c'ninja'), &char(c'cmake'), &char(c'sqlite'), &char(c'node'), &char(c'go'), &char(c'java')]! {
					for index in 0 .. 3 {
						C.snprintf(&path[0], path.len, c'%s/work/qualification/%s/command-%d.log', output, name, index)
						emit_command_log(&path[0])
					}
				}
			}
			check(status == 0, 381)
			C.snprintf(&path[0], path.len, c'%s/work/qualification/report.json', output)
			emit_receipt(&path[0], c'vinix-native', false)
			if ci {
				C.snprintf(&path[0], path.len, c'%s/work/ci-account.json', output)
				private_receipt(&path[0], c'"credential_absent":true')
				C.usleep(1100000)
			}
			C.snprintf(&path[0], path.len, c'%s/work/qualification/http/server.json', output)
			proof := C.open(&path[0], C.O_RDONLY)
			if proof >= 0 {
				check(C.close(proof) == 0, 401)
				emit_receipt(&path[0], c'group_retired', false)
				C.snprintf(&path[0], path.len, c'%s/work/qualification/http/server.conf', output)
				mut config := C.stat{}
				check(C.stat(&path[0], &config) == 0 && config.st_uid == 1000 && config.st_mode & 0o777 == 0o600, 402)
				C.puts(c'DEVELOPMENT HTTP PASS: UID 1000, authenticated loopback server, CGI, private credentials, traversal refusal and owned retirement')
			}
		}
		if ci { ci_finish() }
		C.puts(c'DEVELOPMENT REFERENCE PASS: UID 1000, pinned SDK/runtime/tools, two fresh workspaces, real reference projects and artifact receipts')
	}
}
