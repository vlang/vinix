// SPDX-License-Identifier: GPL-2.0-or-later
// Host selection for fresh iOS builds and VM captures. Guest inputs stay ARM64.
module hosttools

import os

#include <fcntl.h>

pub fn platform() string {
	$if macos {
		return 'macos'
	}
	$if linux {
		return 'linux'
	}
	return 'unsupported'
}

pub fn architecture() string {
	$if arm64 {
		return 'arm64'
	}
	$if amd64 {
		return 'amd64'
	}
	return 'unsupported'
}

fn resolve_executable(value string) !string {
	if value == '' || value.contains_any('\x00\r\n') {
		return error('empty or invalid executable path')
	}
	path := if value.contains('/') {
		os.abs_path(value)
	} else {
		os.find_abs_path_of_executable(value)!
	}
	if !os.is_file(path) || !os.is_executable(path) {
		return error('not an executable file: ' + path)
	}
	// Keep the invocation name: ld.lld can be a symlink to the lld dispatcher.
	return os.abs_path(path)
}

// An explicit invalid override is an error; it never silently selects a fallback.
pub fn executable(variable string, defaults []string) !string {
	if value := os.getenv_opt(variable) {
		return resolve_executable(value) or { return error(variable + ': ' + err.msg()) }
	}
	for value in defaults {
		if path := resolve_executable(value) { return path }
	}
	return error('cannot find ' + variable + '; set it to an executable path')
}

pub fn directory(variable string, fallback string) !string {
	value := os.getenv_opt(variable) or { fallback }
	if value == '' || value.contains_any('\x00\r\n') || !os.is_dir(value) {
		return error(variable + ' must name an existing directory: ' + value)
	}
	return os.real_path(value)
}

pub fn file(variable string, fallback string) !string {
	value := os.getenv_opt(variable) or { fallback }
	if value == '' || value.contains_any('\x00\r\n') || !os.is_file(value) {
		return error(variable + ' must name an existing regular file: ' + value)
	}
	return os.real_path(value)
}

fn default_ca_bundle(host string) !string {
	return match host {
		'linux' { '/etc/ssl/certs/ca-certificates.crt' }
		'macos' { '/etc/ssl/cert.pem' }
		else { return error('unsupported CA-bundle host: ' + host) }
	}
}

// Selection validates a readable PEM bundle; the guest TLS implementation
// still parses certificates and performs its existing trust checks.
pub fn ca_bundle() !string {
	path := file('VINIX_IOS_CA_BUNDLE', default_ca_bundle(platform())!)!
	content := os.read_file(path)!
	begin := '-----BEGIN CERTIFICATE-----'
	end := '-----END CERTIFICATE-----'
	first_begin := content.index(begin) or { -1 }
	first_end := content.index(end) or { -1 }
	if first_begin < 0 || first_end <= first_begin || content.count(begin) != content.count(end) {
		return error('VINIX_IOS_CA_BUNDLE must contain PEM certificates: ' + path)
	}
	return path
}

// QEMU -drive parses comma-separated key/value options after argv parsing.
// Double commas inside a file value so they remain part of the file name.
pub fn qemu_drive_file(path string) !string {
	if path == '' || path.contains_any('\x00\r\n') { return error('invalid QEMU drive file path') }
	return path.replace(',', ',,')
}

pub fn toolchain(root string) !string {
	path := directory('VINIX_IOS_TOOLCHAIN', root + '/build/ios/fortnite/ns-calendar-checks/toolchain')!
	resolve_executable(path + '/v')!
	if !os.is_dir(path + '/vlib') { return error('V toolchain lacks vlib: ' + path) }
	return path
}

pub fn clang() !string {
	defaults := if platform() == 'macos' {
		['/opt/homebrew/opt/llvm/bin/clang', 'clang']
	} else {
		['clang']
	}
	return executable('VINIX_IOS_CLANG', defaults)
}

pub fn linker(compiler string) !string {
	return executable('VINIX_IOS_LD', [os.dir(compiler) + '/ld.lld', 'ld.lld'])
}

pub fn bsdtar() !string {
	defaults := if platform() == 'macos' { ['/usr/bin/tar', 'bsdtar'] } else { ['bsdtar'] }
	path := executable('VINIX_IOS_BSDTAR', defaults)!
	version := os.exec([path, '--version'])
	if version.exit_code != 0 || !version.output.to_lower().contains('bsdtar') {
		return error('VINIX_IOS_BSDTAR requires libarchive bsdtar for streaming archive overlays: ' + path)
	}
	return path
}

pub fn acceleration(host string, arch string, requested string) !(string, string) {
	if host !in ['linux', 'macos'] || arch !in ['arm64', 'amd64'] {
		return error('unsupported iOS VM host: ' + host + '/' + arch)
	}
	accel := if requested == '' {
		if host == 'macos' && arch == 'arm64' { 'hvf' } else { 'tcg' }
	} else {
		requested
	}
	if accel !in ['tcg', 'hvf', 'kvm'] || (accel == 'hvf' && (host != 'macos' || arch != 'arm64'))
		|| (accel == 'kvm' && (host != 'linux' || arch != 'arm64')) {
		return error('unsupported VINIX_IOS_ACCEL=' + accel + ' for ' + host + '/' + arch)
	}
	cpu := if accel == 'tcg' { 'max' } else { 'host' }
	return accel, cpu
}

pub struct VmTools {
pub:
	qemu          string
	accel         string
	cpu           string
	firmware_code string
	firmware_vars string
}

fn firmware_file(path string) !string {
	if path == '' || path.contains_any('\x00\r\n') || !os.is_file(path) || os.file_size(path) != 64 * 1024 * 1024 {
		return error('AArch64 virt pflash input must be a regular 64 MiB file: ' + path)
	}
	return os.real_path(path)
}

pub fn vm_tools() !VmTools {
	host := platform()
	accel, cpu := acceleration(host, architecture(), os.getenv('VINIX_IOS_ACCEL'))!
	defaults := if host == 'macos' {
		['/opt/homebrew/bin/qemu-system-aarch64', 'qemu-system-aarch64']
	} else {
		['qemu-system-aarch64']
	}
	qemu := executable('VINIX_IOS_QEMU', defaults)!
	mut code := ''
	if value := os.getenv_opt('VINIX_IOS_FIRMWARE_CODE') {
		code = firmware_file(value)!
	} else {
		candidates := if host == 'macos' {
			['/opt/homebrew/share/qemu/edk2-aarch64-code.fd']
		} else {
			['/usr/share/AAVMF/AAVMF_CODE.fd', '/usr/share/qemu/edk2-aarch64-code.fd']
		}
		for candidate in candidates {
			if path := firmware_file(candidate) {
				code = path
				break
			}
		}
		if code == '' {
			return error('set VINIX_IOS_FIRMWARE_CODE to AArch64 virt pflash firmware')
		}
	}
	mut vars := ''
	if value := os.getenv_opt('VINIX_IOS_FIRMWARE_VARS') {
		vars = firmware_file(value)!
	} else if host == 'linux' {
		// Preserve the historical Mac capture's blank variable store. Linux may
		// use a packaged matching template, copied privately by the VM caller.
		for candidate in [os.dir(code) + '/AAVMF_VARS.fd', os.dir(code) + '/edk2-arm-vars.fd'] {
			if path := firmware_file(candidate) {
				vars = path
				break
			}
		}
	}
	return VmTools{qemu, accel, cpu, code, vars}
}

// O_EXCL preserves existing files and symlinks, including dangling links.
// ftruncate creates a zero-filled sparse extent without a platform mkfile tool.
pub fn sparse_file(path string, bytes u64) ! {
	if bytes == 0 || bytes > 0x7fffffffffffffff { return error('invalid sparse-file size') }
	fd := unsafe { C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600) }
	if fd < 0 { return os.error_posix() }
	defer { C.close(fd) }
	if C.ftruncate(fd, bytes) != 0 {
		failure := os.error_posix()
		os.rm(path) or {}
		return failure
	}
}
