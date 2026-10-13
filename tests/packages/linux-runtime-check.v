// SPDX-License-Identifier: GPL-2.0-or-later
// Real dynamically linked Linux payload through a signed, isolated musl runtime.
module main

import crypto.sha256
import hwhost
import json2
import os
import time

struct Artifact {
	role   string
	bytes  u64
	sha256 string
}

struct Receipt {
	format       int = 1
	architecture string
	completed_at i64
	platform     string = 'qemu'
	kind         string = 'linux'
	sdk          int    = 1
	scenario     string = 'packages-linux'
	artifacts    []Artifact
}

fn artifact(role string, path string) !Artifact {
	bytes := os.read_bytes(path)!
	return Artifact{ role: role, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
}

fn invoke(command []string) ! {
	mut process := os.new_process(command[0])
	process.set_args(command[1..])
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${command[0]} failed (${code})') }
}

fn compiler_output(command []string) !string {
	mut process := os.new_process(command[0])
	process.set_args(command[1..])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('compiler lookup failed: ${output}') }
	return output.trim_space()
}

fn linux_suite(work string, repository string) !hwhost.Suite {
	mut binaries := [hwhost.RootBinary{ source: work + '/usr/bin/vinix-sandbox', path: 'usr/bin/vinix-sandbox' }]
	for name in ['linux-probe', 'linux-runner', 'musl', 'linux-library'] {
		binaries << hwhost.RootBinary{ source: work + '/' + name, path: 'usr/share/package-fixtures/' + name }
	}
	copying := if work == '' { '' } else { os.read_file(repository + '/LICENSE')! }
	musl_copyright := if work == '' {
		''
	} else {
		os.read_file(os.getenv_opt('VINIX_MUSL_COPYRIGHT') or { repository + '/build-support/musl/COPYRIGHT' })!
	}
	return hwhost.Suite{
		name:         'package-linux-runtime'
		guest:        'tests/accounts/guest'
		module_paths: ['.', 'tools/accounts', 'tools/security-events', 'tools/keyring']
		programs:     [
			hwhost.Program{ source: 'tools/packages/main.v', path: 'usr/bin/vinix-package' },
			hwhost.Program{ source: 'tools/accounts/account.v', path: 'usr/sbin/vinix-account' },
			hwhost.Program{ source: 'tools/accounts/session.v', path: 'usr/sbin/vinix-session' },
		]
		binaries:     binaries
		files:        [
			hwhost.RootFile{ path: 'etc/passwd', text: 'root:x:0:0:root:/root:/bin/sh\n' },
			hwhost.RootFile{ path: 'etc/group', text: 'root:x:0:\ntty:x:5:\n' },
			hwhost.RootFile{ path: 'etc/vinix/auth.conf', text: 'scrypt_ln = 10\n' },
			hwhost.RootFile{ path: 'usr/share/package-fixtures/COPYING', text: copying },
			hwhost.RootFile{ path: 'usr/share/package-fixtures/musl-COPYRIGHT', text: musl_copyright },
		]
		directories:  ['run', 'home', 'var/log', 'tmp:1777']
		scenarios:    [hwhost.Scenario{
			name:     'packages-linux'
			arches:   ['aarch64', 'x86_64']
			about:    'prepared-root import and signed musl loader/library execution under real sandbox enforcement'
			required: ['HWTEST START packages-linux', 'PACKAGE SIGNING', 'PACKAGE CATALOG', 'PACKAGE RELEASE', 'PACKAGE REVIEW', 'PACKAGE TRUST REVIEW', 'PACKAGE CONFIGURATION', 'PACKAGE ORGANIZATION', 'PACKAGE DOCUMENTS', 'PACKAGE DEPLOYMENT', 'PACKAGE PROGRESS', 'PACKAGE OFFLINE', 'PACKAGE MIRROR REVIEW', 'PACKAGE REPOSITORY', 'PACKAGE UPDATES', 'PACKAGE LINUX IMPORT',
				'PACKAGE LOCKED MIRROR', 'HWTEST PASS packages-linux']
			ending:   .poweroff
			timeout:  180
		}]
	}
}

fn require_dynamic_payload(path string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] {
		return error('Linux probe is not ELF64 little-endian')
	}
	if bytes[16] != 3 || bytes[17] != 0 {
		return error('Linux probe must be a position-independent executable; a fixed image can collide with the explicit loader')
	}
	mut offset := u64(0)
	for i in 0 .. 8 { offset |= u64(bytes[32 + i]) << (i * 8) }
	width := int(bytes[54]) | (int(bytes[55]) << 8)
	count := int(bytes[56]) | (int(bytes[57]) << 8)
	if width < 56 || offset > u64(bytes.len) || u64(width) * u64(count) > u64(bytes.len) - offset {
		return error('Linux probe has invalid program headers')
	}
	for index in 0 .. count {
		start := int(offset) + index * width
		// PT_INTERP and PT_DYNAMIC are required, rather than an accidentally
		// static fixture which would never exercise the explicit musl loader.
		if bytes[start..start + 4] == [u8(3), 0, 0, 0] {
			for other in 0 .. count {
				at := int(offset) + other * width
				if bytes[at..at + 4] == [u8(2), 0, 0, 0] { return }
			}
		}
	}
	return error('Linux probe must contain PT_INTERP and PT_DYNAMIC')
}

fn stage_linux(repository string, work string, architecture string) ! {
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	cc := os.find_abs_path_of_executable(os.getenv_opt('VINIX_MUSL_CC_' + architecture.to_upper()) or { architecture + '-linux-musl-gcc' })!
	arch := if architecture == 'aarch64' { 'arm64' } else { 'amd64' }
	for output, input in {
		'linux-probe':   'tests/packages/linux-probe.v'
		'linux-runner':  'tools/packages/linux-runner.v'
		'linux-library': 'tests/packages/linux-library.v'
	} {
		mut flags := ['-os', 'linux', '-arch', arch, '-gc', 'none', '-d', 'no_backtrace', '-d',
			'no_segfault_handler']
		if output == 'linux-library' { flags << '-shared' }
		invoke([v, ...flags, '-o', work + '/' + output + '.c', repository + '/' + input])!
	}
	invoke([cc, '-shared', '-fPIC', '-O2', '-std=gnu11', '-D_GNU_SOURCE', work + '/linux-library.c',
		'-Wl,-soname,libfixture.so.1', '-o', work + '/linux-library', '-lm', '-lpthread'])!
	os.symlink('linux-library', work + '/libfixture.so')!
	invoke([cc, '-fPIE', '-pie', '-O2', '-std=gnu11', '-D_GNU_SOURCE', work + '/linux-probe.c', '-L' + work, '-lfixture',
		'-o', work + '/linux-probe', '-lm', '-lpthread'])!
	require_dynamic_payload(work + '/linux-probe')!
	invoke([cc, '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', work + '/linux-runner.c', '-o',
		work + '/linux-runner', '-lm', '-lpthread'])!
	loader := compiler_output([cc, '-print-file-name=libc.so'])!
	if !os.is_file(loader) {
		return error('target musl compiler has no dynamic libc.so: ${loader}')
	}
	os.cp(loader, work + '/musl')!
	if sandbox := os.getenv_opt('VINIX_LINUX_SANDBOX') {
		// RootBinary admission checks ELF class and target before guest boot.
		if !os.is_file(sandbox) { return error('VINIX_LINUX_SANDBOX must select an existing native sandbox') }
		os.mkdir_all(work + '/usr/bin')!
		os.cp(sandbox, work + '/usr/bin/vinix-sandbox')!
	} else {
		invoke([repository + '/build-support/security-tools/stage', '--arch', architecture, '--staging', work])!
	}
}

fn check() !int {
	args := os.args[1..]
	options := hwhost.parse_options(args)!
	repository := hwhost.find_root(@FILE)!
	if options.help || options.list {
		return hwhost.run_suite(linux_suite('', repository)!, args, @FILE)
	}
	if !os.is_file(options.kernel) { return error('--kernel is not a file') }
	work := os.temp_dir() + '/vinix-package-linux-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	kernel := work + '/kernel'
	os.cp(options.kernel, kernel)!
	stage_linux(repository, work, options.arch)!
	status := hwhost.run_suite(linux_suite(work, repository)!, [...args, '--kernel', kernel], @FILE)
	if status == 0 && options.state_dir != '' {
		root := os.join_path(options.state_dir, 'guest', 'root')
		receipt := Receipt{
			architecture: options.arch
			completed_at: time.now().unix()
			artifacts:    [
				artifact('kernel', kernel)!,
				artifact('sandbox', work + '/usr/bin/vinix-sandbox')!,
				artifact('dynamic-linux-payload', work + '/linux-probe')!,
				artifact('shared-linux-library', work + '/linux-library')!,
				artifact('musl-loader', work + '/musl')!,
				artifact('static-linux-runner', work + '/linux-runner')!,
				artifact('package-service', root + '/usr/bin/vinix-package')!,
				artifact('guest-init', options.state_dir + '/guest/init')!,
				artifact('account-manager', root + '/usr/sbin/vinix-account')!,
				artifact('session-runner', root + '/usr/sbin/vinix-session')!,
				artifact('serial-log', options.state_dir + '/packages-linux/serial.log')!,
			]
		}
		os.write_file(options.state_dir + '/qualification.json', json2.encode(receipt) + '\n')!
	}
	return status
}

fn main() {
	status := check() or {
		eprintln(err)
		exit(1)
	}
	exit(status)
}
