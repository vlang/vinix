// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import os

fn policy_expect(condition bool, message string) {
	if !condition { panic('wine-native-policy control: ' + message) }
}

fn test_native_policy_exact_target_arguments_preserve_warnings() {
	for target in ['aarch64', 'x86_64'] {
		arguments := native_target_c_arguments('/tools/clang', '/tools/ld', '/resource',
			target, '/sysroot', '/gcc', '/work/program.c', '/work/program')!
		policy_expect(arguments == ['/tools/clang', '--no-default-config',
			'--target=' + target + '-linux-musl', '--sysroot=/sysroot',
			'--gcc-install-dir=/gcc', '-resource-dir=/resource', '-fuse-ld=/tools/ld',
			'-static', '-O2', '-D_GNU_SOURCE', '-fno-stack-protector',
			'/work/program.c', '-lm', '-lpthread', '-o', '/work/program'], 'exact target argv')
		policy_expect(arguments.filter(it == '-w' || it.starts_with('-Wno')).len == 0,
			'warning suppression absent')
	}
}

fn test_native_policy_refuses_unsupported_targets_and_paths() {
	for target in ['arm64', '', 'x86_64 -w'] {
		mut refused := false
		native_target_c_arguments('/clang', '/ld', '/resource', target, '/sysroot', '/gcc', '/in', '/out') or {
			refused = err.msg() == 'unsupported standalone target'
			[]string{}
		}
		policy_expect(refused, 'unsupported target refused')
	}
	for bad in ['relative', '', '/absolute\n-w', '/absolute\r-w'] {
		for position in 0 .. 7 {
			mut paths := ['/clang', '/ld', '/resource', '/sysroot', '/gcc', '/in', '/out']
			paths[position] = bad
			mut refused := false
			native_target_c_arguments(paths[0], paths[1], paths[2], 'aarch64', paths[3], paths[4], paths[5], paths[6]) or {
				refused = err.msg() == 'standalone compiler paths must be absolute single-line paths'
				[]string{}
			}
			policy_expect(refused, 'invalid compiler path refused')
		}
	}
}

fn test_native_policy_clears_and_records_compiler_overrides() {
	selected := ['VFLAGS', 'CFLAGS', 'LDFLAGS', 'VTEST_ONLY_FN', 'V3CACHE',
		'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH',
		'OBJCPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'COMPILER_PATH', 'GCC_EXEC_PREFIX',
		'CCC_OVERRIDE_OPTIONS', 'CLANG_CONFIG_FILE_SYSTEM_DIR',
		'CLANG_CONFIG_FILE_USER_DIR', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET']
	mut original := map[string]string{}
	for name in selected { if value := os.getenv_opt(name) { original[name] = value } }
	if value := os.getenv_opt('VINIX_WINE_POLICY_UNRELATED') {
		original['VINIX_WINE_POLICY_UNRELATED'] = value
	}
	defer {
		for name in selected {
			if name in original { os.setenv(name, original[name], true) }
			else { os.unsetenv(name) }
		}
		if 'VINIX_WINE_POLICY_UNRELATED' in original {
			os.setenv('VINIX_WINE_POLICY_UNRELATED', original['VINIX_WINE_POLICY_UNRELATED'], true)
		} else { os.unsetenv('VINIX_WINE_POLICY_UNRELATED') }
	}
	for name in selected { os.setenv(name, 'injected-' + name, true) }
	os.setenv('VINIX_WINE_POLICY_UNRELATED', 'retained', true)
	recorded := native_clear_compiler_environment()
	policy_expect(recorded.len == selected.len, 'all selected compiler overrides covered')
	for name in selected {
		policy_expect(name in recorded && recorded[name] == 'injected-' + name,
			'inherited override recorded')
		if _ := os.getenv_opt(name) { policy_expect(false, 'override absent after clearing') }
	}
	policy_expect(os.getenv('VINIX_WINE_POLICY_UNRELATED') == 'retained', 'unrelated entry retained')
	for _, value in native_clear_compiler_environment() {
		policy_expect(value == '<unset>', 'second clearing records absence')
	}
}

fn test_native_policy_exact_admission_and_output_limits() {
	policy_expect(native_free_floor(true) == 2 * 1024 * 1024, 'initial/pre-VM floor 2GiB')
	policy_expect(native_free_floor(false) == 1024 * 1024, 'child floor 1GiB')
	for timeout in [60000, 90000] {
		limits := native_capture_limits(timeout)
		policy_expect(limits.timeout_ms == timeout && limits.min_free_kib == 1024 * 1024,
			'build/VM timeout and floor selected')
		policy_expect(limits.file_bytes == 128 * 1024 * 1024
			&& limits.total_bytes == 256 * 1024 * 1024
			&& limits.log_bytes == 256 * 1024 && limits.serial_bytes == 6 * 1024 * 1024,
			'capture output thresholds retained')
	}
}

fn test_native_policy_assertions_are_active() {
	if os.getenv('VINIX_WINE_POLICY_ASSERT_SENTINEL') == '1' {
		policy_expect(false, 'wine-native-policy intentional assertion sentinel')
	}
}
