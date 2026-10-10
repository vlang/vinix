// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the suite needs from the machine it runs on: the checkout, a V
// compiler, QEMU and its firmware. Each is looked for where a default
// installation puts it and can be named through the environment instead, so
// no path of one particular machine is written down here.
module hwhost

import os

pub struct Host {
pub:
	root string // the checkout
	arch string // the guest architecture
	v    string // the V compiler
	qemu string
	// UEFI firmware: the code, and for aarch64 the variable store each boot
	// gets a private copy of.
	firmware      string
	firmware_vars string
}

fn environment_or(name string, fallback string) string {
	value := os.getenv(name)
	return if value == '' { fallback } else { value }
}

// The checkout, from where the controller's own source was compiled.
// VINIX_ROOT names another one; the working directory is the last resort for
// a binary that has been moved away from its source.
pub fn find_root(controller_source string) !string {
	mut candidates := []string{}
	if override := os.getenv_opt('VINIX_ROOT') {
		candidates << override
	} else {
		candidates << os.join_path(os.dir(os.real_path(controller_source)), '..', '..')
		mut directory := os.getwd()
		for directory != '' && directory != '/' {
			candidates << directory
			directory = os.dir(directory)
		}
	}
	for candidate in candidates {
		if os.is_file(os.join_path(candidate, 'tests', 'hardware-platform', 'run.v'))
			&& os.is_file(os.join_path(candidate, 'build-support', 'find-v.sh')) {
			return os.real_path(candidate)
		}
	}
	return error('cannot find the Vinix checkout; set VINIX_ROOT')
}

// The checkout a git worktree was made from, or '' for a main checkout.
//
// In a worktree `.git` is a file that names its directory inside the main
// checkout's `.git/worktrees`.
fn main_checkout(root string) string {
	pointer := os.join_path(root, '.git')
	if !os.is_file(pointer) {
		return ''
	}
	text := os.read_file(pointer) or { return '' }
	for line in text.split_into_lines() {
		if !line.starts_with('gitdir:') {
			continue
		}
		directory := line.all_after('gitdir:').trim_space()
		marker := '/.git/worktrees/'
		if directory.contains(marker) {
			return directory.all_before(marker)
		}
	}
	return ''
}

// Where an untracked build input is. A worktree has none of its own: the
// sysroot, the boot loader and the downloads are made once in the main
// checkout, and a test in a worktree borrows them rather than rebuild them.
pub fn shared_path(root string, relative string) string {
	own := os.join_path(root, relative)
	if os.exists(own) {
		return own
	}
	main := main_checkout(root)
	if main != '' {
		borrowed := os.join_path(main, relative)
		if os.exists(borrowed) {
			return borrowed
		}
	}
	return own
}

// The compiler the launcher chose (build-support/find-v.sh exports V), or
// the one that script would choose.
fn find_v() !string {
	for name in ['V', 'VINIX_V_COMPILER'] {
		mut value := os.getenv(name)
		if value == '' {
			continue
		}
		if os.is_dir(value) {
			value = os.join_path(value, 'v')
		}
		if !value.contains('/') {
			value = os.find_abs_path_of_executable(value) or { value }
		}
		if os.is_executable(value) {
			return value
		}
		return error('${name} does not name a V compiler: ${value}')
	}
	if on_path := os.find_abs_path_of_executable('v') {
		return on_path
	}
	for candidate in [os.join_path(os.home_dir(), 'code', 'v', 'v'),
		os.join_path(os.home_dir(), 'v', 'v')] {
		if os.is_executable(candidate) {
			return candidate
		}
	}
	return error('cannot find a V compiler; set V or VINIX_V_COMPILER')
}

// Firmware ships beside QEMU, in share/qemu next to its bin. A package
// manager's bin is often a directory of links, so the place the link points
// to is tried as well.
fn find_firmware(qemu string, file string, variable string) !string {
	if override := os.getenv_opt(variable) {
		if !os.is_file(override) {
			return error('${variable} is not a file: ${override}')
		}
		return override
	}
	for binary in [qemu, os.real_path(qemu)] {
		candidate := os.join_path(os.dir(os.dir(binary)), 'share', 'qemu', file)
		if os.is_file(candidate) {
			return candidate
		}
	}
	return error('cannot find ${file} beside ${qemu}; set ${variable}')
}

pub fn find_host(root string, arch string, qemu_option string) !Host {
	upper := arch.to_upper()
	mut qemu := qemu_option
	if qemu == '' {
		qemu = environment_or('VINIX_QEMU_${upper}', 'qemu-system-${arch}')
	}
	if !qemu.contains('/') {
		qemu = os.find_abs_path_of_executable(qemu) or {
			return error('${qemu} is not on PATH; pass --qemu or set VINIX_QEMU_${upper}')
		}
	}
	if !os.is_executable(qemu) {
		return error('not an executable: ${qemu}')
	}
	mut vars := ''
	if arch == 'aarch64' {
		vars = find_firmware(qemu, 'edk2-arm-vars.fd', 'VINIX_OVMF_VARS_AARCH64')!
	}
	return Host{
		root:          root
		arch:          arch
		v:             find_v()!
		qemu:          qemu
		firmware:      find_firmware(qemu, 'edk2-${arch}-code.fd', 'VINIX_OVMF_CODE_${upper}')!
		firmware_vars: vars
	}
}

// How QEMU runs the guest's processor. An AArch64 guest on Apple silicon
// runs on the host's own cores through Hypervisor.framework; everything else
// is emulated, which is slower and is also the only way x86-64 runs there.
// VINIX_HWTEST_TCG=1 asks for emulation where there is a choice.
pub fn (h &Host) accelerator() []string {
	if h.arch == 'aarch64' && os.getenv('VINIX_HWTEST_TCG') != '1' {
		$if macos && arm64 {
			return ['-accel', 'hvf', '-cpu', 'host']
		}
	}
	return ['-accel', 'tcg', '-cpu', 'max']
}
