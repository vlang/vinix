// SPDX-License-Identifier: GPL-2.0-or-later
// Capture the guest build and launch commands for the CString factory checkpoint.
module main

import os
import strings
import time

fn capture(out string, mode string) ! {
	args := [out + '/notification-vm', mode, out]
	mut process := os.new_process(args[0])
	process.set_args(args[1..])
	process.set_redirect_stdio_merged()
	process.run()
	mut output := strings.new_builder(4096)
	watch := time.new_stopwatch()
	mut timed_out := false
	for process.is_alive() {
		output.write_string(process.stdout_read())
		if watch.elapsed().seconds() > 600 {
			timed_out = true
			process.signal_kill()
			break
		}
		time.sleep(20 * time.millisecond)
	}
	output.write_string(process.stdout_slurp())
	process.wait()
	code := if timed_out { 124 } else { process.code }
	process.close()
	if timed_out { output.write_string('\nCHECKPOINT-TIMEOUT: killed after 600 seconds\n') }
	os.write_file(out + '/' + mode + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + output.str())!
	unsafe { output.free() }
	os.write_file(out + '/' + mode + '.status.txt', code.str() + '\n')!
	println('${mode}: ${code}')
	if code != 0 { exit(code) }
}

fn main() {
	if os.args.len != 3 || os.args[1] !in ['build', 'build-output', 'probe'] {
		panic('usage: string-cstring-run build|build-output|probe EXTERNAL_OUT')
	}
	root := os.real_path(os.getwd())
	out := os.abs_path(os.args[2])
	if out == root || out.starts_with(root + '/') { panic('evidence must be external') }
	os.mkdir_all(out + '/tmp')!
	os.setenv('TMPDIR', out + '/tmp', true)
	os.setenv('V_RESOURCE_PATH', root + '/build/ios/fortnite/ns-calendar-checks/toolchain', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('VINIX_IOS_CHECK_NAME', 'notification-center-checks', true)
	if os.args[1] == 'build' {
		for mode in ['build-init', 'build-string-cstring', 'build-bundle-receipt', 'build-cf-string-output', 'build-search-path', 'build-home-directory', 'build-inline-pthread-self', 'build-dictionary-snapshot', 'build-block-byref', 'build-vm-probe', 'build-run-ios-gles'] {
			capture(out, mode)!
		}
	} else if os.args[1] == 'build-output' {
		for mode in ['build-string-cstring', 'build-bundle-receipt', 'build-run-ios-gles'] { capture(out, mode)! }
	} else {
		os.setenv('VINIX_IOS_PROBE_MEMORY_MAX', '2147483648', true)
		os.setenv('VINIX_IOS_VM_GZIP_LEVEL', '9', true)
		capture(out, 'probe-no-ads')!
	}
}
