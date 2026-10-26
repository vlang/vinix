// SPDX-License-Identifier: GPL-2.0-or-later
module winejitstream

import os

// Initial admission and the pre-VM check reserve media/copy space. Every
// guarded child retains the lower floor while its output is monitored.
pub fn native_free_floor(starting bool) u64 {
	return if starting { u64(2 * 1024 * 1024) } else { u64(1024 * 1024) }
}

pub fn native_capture_limits(timeout_ms int) NativeLimits {
	return NativeLimits{
		timeout_ms: timeout_ms
		file_bytes: 128 * 1024 * 1024
		total_bytes: 256 * 1024 * 1024
		log_bytes: 256 * 1024
		serial_bytes: 6 * 1024 * 1024
		min_free_kib: native_free_floor(false)
	}
}

// These affect V options or Clang's default configuration/search paths. Keep
// the inherited values in the receipt and remove them before either compiler.
pub fn native_clear_compiler_environment() map[string]string {
	mut inherited := map[string]string{}
	for name in ['VFLAGS', 'CFLAGS', 'LDFLAGS', 'VTEST_ONLY_FN', 'V3CACHE',
		'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH',
		'OBJC_INCLUDE_PATH', 'OBJCPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'COMPILER_PATH',
		'GCC_EXEC_PREFIX', 'CCC_OVERRIDE_OPTIONS', 'CLANG_CONFIG_FILE_SYSTEM_DIR',
		'CLANG_CONFIG_FILE_USER_DIR', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET'] {
		inherited[name] = os.getenv_opt(name) or { '<unset>' }
		os.unsetenv(name)
	}
	return inherited
}

// The compiler expands @vmodules even when the variable was inherited unset.
// A private, empty, canonical directory makes that search root explicit.
pub fn native_require_empty_modules(path string) ! {
	if !os.is_abs_path(path) || path.contains(os.path_delimiter)
		|| path.contains('\n') || path.contains('\r') {
		return error('module search root must be one absolute path')
	}
	info := os.lstat(path) or { return error('module search root unavailable: ' + path) }
	if info.get_filetype() != .directory || os.real_path(path) != path {
		return error('module search root must be a canonical ordinary directory')
	}
	if os.ls(path)!.len != 0 { return error('private module search root must remain empty') }
}

pub fn native_target_c_arguments(clang string, linker string, resource string,
	target string, sysroot string, gcc string, source string, output string) ![]string {
	if target !in ['aarch64', 'x86_64'] { return error('unsupported standalone target') }
	for value in [clang, linker, resource, sysroot, gcc, source, output] {
		if !os.is_abs_path(value) || value.contains('\n') || value.contains('\r') {
			return error('standalone compiler paths must be absolute single-line paths')
		}
	}
	return [clang, '--no-default-config', '--target=' + target + '-linux-musl',
		'--sysroot=' + sysroot, '--gcc-install-dir=' + gcc, '-resource-dir=' + resource,
		'-fuse-ld=' + linker, '-static', '-O2', '-D_GNU_SOURCE', '-fno-stack-protector',
		source, '-lm', '-lpthread', '-o', output]
}
