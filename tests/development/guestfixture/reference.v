// SPDX-License-Identifier: GPL-2.0-or-later
module guestfixture

fn reference_checks() {
	unsafe {
		marker := C.open(c'/home/developer/reference-build.json', C.O_RDONLY)
		if marker < 0 { return }
		check(C.close(marker) == 0, 380)
		private_receipt(c'/home/developer/reference-build.json', c'/opt/reference')
		for output in [&char(c'/home/developer/reference-a'), &char(c'/home/developer/reference-b')]! {
			status := command(c'/usr/bin/vinix-build', c'build', c'/home/developer/reference-build.json', output)
			mut st := C.stat{}
			check(C.stat(output, &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o700, 383)
			mut path := [512]char{}
			for name in [&char(c'cc'), &char(c'make'), &char(c'ninja'), &char(c'cmake'), &char(c'sqlite3'), &char(c'node'), &char(c'go')]! {
				C.snprintf(&path[0], path.len, c'%s/version-%s.log', output, name)
				emit_command_log(&path[0])
			}
			C.snprintf(&path[0], path.len, c'%s/qualify.log', output)
			emit_command_log(&path[0])
			C.snprintf(&path[0], path.len, c'%s/receipt.json', output)
			emit_receipt(&path[0], c'Vinix', false)
			if status != 0 {
				for name in [&char(c'make'), &char(c'ninja'), &char(c'cmake'), &char(c'sqlite'), &char(c'node'), &char(c'go')]! {
					for index in 0 .. 3 {
						C.snprintf(&path[0], path.len, c'%s/work/qualification/%s/command-%d.log', output, name, index)
						emit_command_log(&path[0])
					}
				}
			}
			check(status == 0, 381)
			C.snprintf(&path[0], path.len, c'%s/work/qualification/report.json', output)
			emit_receipt(&path[0], c'vinix-native', false)
		}
		C.puts(c'DEVELOPMENT REFERENCE PASS: UID 1000, pinned SDK/runtime/tools, two fresh workspaces, real reference projects and artifact receipts')
	}
}
