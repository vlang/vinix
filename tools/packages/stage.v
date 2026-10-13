// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.pkgcore

fn invoke(program string, arguments []string) ! {
	mut process := os.new_process(program)
	process.set_args(arguments)
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program} failed (${code})') }
}

fn stage() ! {
	mut architecture := ''
	mut staging := ''
	mut compiler := ''
	mut compiler_args := []string{}
	mut arguments := os.args[1..].clone()
	for arguments.len > 0 {
		if arguments.len < 2 {
			return error('usage: stage.v --arch aarch64|x86_64 --staging DIR [--cc COMPILER]')
		}
		match arguments[0] {
			'--arch' { architecture = arguments[1] }
			'--staging' { staging = os.abs_path(arguments[1]) }
			'--cc' { compiler = arguments[1] }
			'--cc-argv' { compiler_args = json2.decode[[]string](arguments[1])! }
			else { return error('unknown staging option: ${arguments[0]}') }
		}
		arguments = arguments[2..].clone()
	}
	if architecture !in ['aarch64', 'x86_64'] || staging == '' || staging == '/' || !os.is_dir(staging) {
		return error('staging needs an existing target directory and supported architecture')
	}
	if compiler == '' { compiler = os.getenv('VINIX_MUSL_CC_' + architecture.to_upper()) }
	if compiler == '' { compiler = architecture + '-linux-musl-gcc' }
	// A compiler is an executable path, never shell text.
	if compiler_args.len == 0 { compiler_args = [compiler] }
	cc := os.find_abs_path_of_executable(compiler_args[0])!
	configured_v := os.getenv('V')
	compiler_v := if configured_v == '' { 'v' } else { configured_v }
	v := os.find_abs_path_of_executable(compiler_v)!
	repository := os.dir(os.dir(os.dir(@FILE)))
	work := os.join_path(os.temp_dir(), 'vinix-package-stage-' + os.getpid().str())
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	for tool, input in {
		'usr/bin/vinix-package':  'tools/packages/main.v'
		'usr/sbin/vinix-session': 'tools/accounts/session.v'
		'usr/libexec/vinix/vinix-linux-runner': 'tools/packages/linux-runner.v'
	} {
		source := work + '/' + os.file_name(tool) + '.c'
		invoke(v, ['-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
			if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', source,
			repository + '/' + input])!
		binary := work + '/' + os.file_name(tool)
		invoke(cc, [...compiler_args[1..], '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', source,
			'-o', binary, '-lm', '-lpthread'])!
		data := os.read_bytes(binary)!
		if data.len < 20 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| int(data[18]) + (int(data[19]) << 8) != if architecture == 'aarch64' {
				183
			} else {
				62
			} {
			return error('${tool} compiler produced the wrong target architecture')
		}
		os.mkdir_all(os.dir(staging + '/' + tool))!
		os.cp(binary, staging + '/' + tool + '.new')!
		os.chmod(staging + '/' + tool + '.new', 0o755)!
		os.rename(staging + '/' + tool + '.new', staging + '/' + tool)!
	}
	// Retain the pinned signing implementation's license in binary releases.
	notices := staging + '/usr/share/licenses/vinix-packages'
	os.mkdir_all(notices)!
	os.cp(repository + '/tools/packages/signing/LICENSE', notices + '/ed25519-MIT.txt')!
	os.chmod(notices + '/ed25519-MIT.txt', 0o644)!
	os.cp(repository + '/tools/packages/appsdk/LICENSE', notices + '/application-sdk-MIT.txt')!
	os.chmod(notices + '/application-sdk-MIT.txt', 0o644)!
	software := staging + '/usr/bin/vinix-software'
	if os.exists(software) || os.is_link(software) { os.rm(software)! }
	os.symlink('/usr/bin/vinix-desktop', software)!
	os.mkdir_all(staging + '/etc/vinix-packages')!
	config_path := staging + '/etc/vinix-packages/config.json'
	if !os.exists(config_path) {
		// Releases must enroll their actual public key. Never ship a trusted
		// demonstration key or fall back to unsigned repositories.
		os.write_file(config_path, json2.encode(pkgcore.Config{ architecture: architecture }) + '\n')!
		os.chmod(config_path, 0o644)!
	}
	os.chmod(staging + '/etc/vinix-packages', 0o755)!
	os.mkdir_all(staging + '/usr/share/vinix/actions')!
	// An ordinary desktop authenticates only this fixed reviewed-operation
	// action. Preserve administrator-owned overrides when upgrading an image.
	action := staging + '/usr/share/vinix/actions/packages-change'
	if !os.exists(action) && !os.is_link(action) {
		os.cp(repository + '/tools/accounts/actions/packages-change', action)!
		os.chmod(action, 0o644)!
	}
	config := pkgcore.load_config(staging)!
	if config.architecture != architecture {
		return error('existing package configuration targets another architecture')
	}
	os.mkdir_all(staging + '/var/lib/vinix-packages')!
	os.chmod(staging + '/var/lib/vinix-packages', 0o755)!
	os.mkdir_all(staging + '/usr/share/applications')!
	registration := staging + '/usr/share/applications/vinix-packages'
	if !os.exists(registration) && !os.is_link(registration) {
		os.symlink('/var/lib/vinix-packages/current/share/applications', registration)!
	}
	println('Staged signed package service and Software launcher (${architecture})')
}

fn main() {
	stage() or {
		eprintln('package staging: ${err}')
		exit(1)
	}
}
