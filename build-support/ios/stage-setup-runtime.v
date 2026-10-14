// SPDX-License-Identifier: GPL-2.0-or-later
// Include a built static iOS runner as an optional first-boot payload.
module main

import os

fn main() {
	if os.args.len != 3 {
		eprintln('usage: v run build-support/ios/stage-setup-runtime.v BUILT_RUN_IOS IMAGE_ROOT')
		exit(1)
	}
	source := os.real_path(os.args[1])
	root := os.real_path(os.args[2])
	if !os.is_file(source) || !os.is_executable(source) || !os.is_dir(root) {
		eprintln('a built executable and an existing image root are required')
		exit(1)
	}
	destination := '${root}/usr/share/vinix/optional/ios-runtime'
	os.mkdir_all(destination) or {
		eprintln(err)
		exit(1)
	}
	os.cp(source, '${destination}/run-ios') or {
		eprintln(err)
		exit(1)
	}
	os.chmod('${destination}/run-ios', 0o755) or {
		eprintln(err)
		exit(1)
	}
	println('Staged the native ARM64 iOS runtime for the first-boot software picker.')
}
