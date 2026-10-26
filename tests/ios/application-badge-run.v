// SPDX-License-Identifier: GPL-2.0-or-later
// Capture the guest build and launch commands for the UIApplication badge clearing checkpoint.
module main

import os
import strings
import time

fn capture(out string, modes []string) ! {
	mut processes := []&os.Process{}
	mut outputs := []strings.Builder{}
	mut codes := []int{len: modes.len}
	mut finished := []bool{len: modes.len}
	for mode in modes {
		mut process := os.new_process(out + '/notification-vm')
		process.set_args([mode, out])
		process.set_redirect_stdio_merged()
		process.run()
		processes << process
		outputs << strings.new_builder(4096)
	}
	watch := time.new_stopwatch()
	for finished.any(!it) {
		for i, mut process in processes {
			if finished[i] { continue }
			outputs[i].write_string(process.stdout_read())
			timed_out := process.is_alive() && watch.elapsed().seconds() > 600
			if process.is_alive() && !timed_out { continue }
			if timed_out { process.signal_kill() }
			outputs[i].write_string(process.stdout_slurp())
			process.wait()
			codes[i] = if timed_out { 124 } else { process.code }
			process.close()
			if timed_out { outputs[i].write_string('\nCHECKPOINT-TIMEOUT: killed after 600 seconds\n') }
			mode := modes[i]
			args := [out + '/notification-vm', mode, out]
			os.write_file(out + '/' + mode + '.log', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + outputs[i].str())!
			unsafe { outputs[i].free() }
			os.write_file(out + '/' + mode + '.status.txt', codes[i].str() + '\n')!
			println('${mode}: ${codes[i]}')
			finished[i] = true
		}
		if finished.any(!it) { time.sleep(20 * time.millisecond) }
	}
	for code in codes { if code != 0 { exit(code) } }
}

fn main() {
	if os.args.len != 3 || os.args[1] !in ['build', 'probe'] {
		panic('usage: application-badge-run build|probe EXTERNAL_OUT')
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
		modes := ['build-init', 'build-application-badge', 'build-window', 'build-string-float', 'build-string-cstring', 'build-bundle-receipt', 'build-cf-string-output', 'build-search-path', 'build-home-directory', 'build-inline-pthread-self', 'build-dictionary-snapshot', 'build-block-byref', 'build-vm-probe', 'build-run-ios-gles']
		// Outputs are independent and tlsbuild locks the shared archive.
		for start := 0; start < modes.len; start += 4 {
			end := if start + 4 < modes.len { start + 4 } else { modes.len }
			capture(out, modes[start..end])!
		}
	} else {
		os.setenv('VINIX_IOS_PROBE_MEMORY_MAX', '2147483648', true)
		os.setenv('VINIX_IOS_VM_GZIP_LEVEL', '9', true)
		capture(out, ['probe-no-ads'])!
	}
}
