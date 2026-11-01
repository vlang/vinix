// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import hosttools

// Share the same compiler/test-filter boundary with standalone fixtures.
// Explicit VINIX_IOS_* tool, SDK and game inputs remain available.
fn isolated_build_environment() map[string]string {
	mut env := os.environ()
	for key in env.keys() {
		if key in ['VFLAGS', 'VEXE', 'VCHILD', 'VNORUN', 'VCOVDIR', 'VBUILD_FACTS', 'VBUILD_DEFINES',
			'CFLAGS', 'CPPFLAGS', 'LDFLAGS'] || key.starts_with('VTEST_')
			|| key.starts_with('V3') || key.starts_with('V_MACOS_V3_')
			|| key.starts_with('V_DIAGNOSTICS_') || key.starts_with('QEMU_') {
			env.delete(key)
		}
	}
	return env
}

// The wrapper uses one owned group for the complete VM driver, including its
// build/archive children and QEMU. The 1800-second guest probe fits inside the
// outer one-hour limit. Existing per-mode log/status names remain unchanged.
pub fn run_vm(root string, out string, mode string) ! {
	$if !linux {
		return error('the guarded VM wrapper requires Linux')
	}
	mut env := isolated_build_environment()
	env['TMPDIR'] = out + '/tmp'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_RESOURCE_PATH'] = hosttools.toolchain(root)!
	env['V_SKIP_VVMRC'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	env['VINIX_IOS_CHECK_NAME'] = 'notification-center-checks'
	env.delete('SWIFT_DETERMINISTIC_HASHING')
	code, output := guarded_command(out, mode, [out + '/notification-vm', mode, out], root,
		env, 3600)!
	if code != 0 || output.contains('runtime error:') || output.contains('ERROR: AddressSanitizer')
		|| output.contains('V panic:') || output.contains('> assert ') {
		eprintln(output)
		return error_with_code('${mode}: VM driver failed; see ${out}/${mode}.log', if code == 0 {
			1
		} else {
			code
		})
	}
	println(mode + ': PASS')
}
