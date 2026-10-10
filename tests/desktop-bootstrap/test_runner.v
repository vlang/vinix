// SPDX-License-Identifier: GPL-2.0-only
// Exercise launcher bootstrap ordering with native V fixture executables.
import hosttest
import os

const dependency_dirs = ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm']
const dependency_files = ['c/nanoprintf.h', 'c/uacpi/acpi.h', 'c/lwip/include/lwip/init.h']

fn write(path string, text string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, text)!
}

fn event(root string, name string) ! {
	mut file := os.open_file(root + '/events', 'a')!
	defer { file.close() }
	file.write_string(name + '\n')!
}

fn dependencies(root string) ! {
	for directory in dependency_dirs { os.mkdir_all(root + '/kernel/' + directory)! }
	for name in dependency_files { write(root + '/kernel/' + name, 'dependency fixture\n')! }
}

fn fake(root string, name string) ! {
	match name {
		'prune-build-artifacts' {
			if expected := os.getenv_opt('TEST_SELECTED_COMPILER') { assert os.getenv('VINIX_V_COMPILER') == expected }
			event(root, 'prune')!
		}
		'v' { println('fixture V compiler') }
		'sysctl', 'nproc' { println('2') }
		'build-qemu-ovmf-aarch64.sh' {
			event(root, 'firmware')!
			write(root + '/boot-image/edk2-aarch64-code-2048x1536.fd', '')!
		}
		'get-deps' {
			event(root, 'deps')!
			dependencies(root)!
		}
		'make' {
			assert os.exists(root + '/kernel/c/lwip/include/lwip/init.h')
			event(root, 'make')!
			write(root + '/kernel/bin/vinix', 'kernel fixture\n')!
		}
		'prepare-desktop-aarch64.sh' {
			assert os.exists(root + '/kernel/bin/vinix')
			event(root, 'prepare')!
		}
		'build-desktop-aarch64.sh' {
			event(root, 'desktop')!
			write(root + '/build-support/init-aarch64/initramfs-desktop.tar', 'desktop fixture\n')!
		}
		'run-aarch64.sh' {
			assert os.args.len >= 2 && os.args[1] == '--no-build'
			event(root, 'boot')!
			println('fixture: reached QEMU runner')
		}
		else { return error('unexpected native launcher fixture: ' + name) }
	}
}

fn check(case_name string) ! {
	work := hosttest.work_dir('', 'vinix-desktop-runner-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	root := work + '/checkout'
	write(root + '/scripts/run-desktop-aarch64.sh', os.read_file(hosttest.root() + '/scripts/run-desktop-aarch64.sh')!)!
	write(root + '/kernel/bin/vinix', 'kernel fixture\n')!
	write(root + '/build-support/init-aarch64/initramfs-desktop.tar', 'desktop fixture\n')!
	// This file is sourced by bash; every executed fake tool is a V binary.
	write(root + '/build-support/find-v.sh', 'printf "compiler\\n" >> "$TEST_EVENTS"\nV="$SCRIPT_DIR/fake-bin/v"\n')!
	for name in ['tools/prune-build-artifacts', 'fake-bin/v', 'fake-bin/sysctl', 'fake-bin/nproc',
		'scripts/build-qemu-ovmf-aarch64.sh', 'kernel/get-deps', 'fake-bin/make',
		'build-support/prepare-desktop-aarch64.sh', 'scripts/build-desktop-aarch64.sh',
		'scripts/run-aarch64.sh'] {
		os.mkdir_all(os.dir(root + '/' + name))!
		os.symlink(os.executable(), root + '/' + name)!
	}
	mut env := map[string]string{}
	for key, value in os.environ() {
		if !key.starts_with('VINIX_') && key != 'V' { env[key] = value }
	}
	env['TEST_EVENTS'] = root + '/events'
	env['PATH'] = root + '/fake-bin:' + os.getenv('PATH')
	env['VINIX_BOOTSTRAP_FIXTURE_ROOT'] = root
	if case_name == 'compiler-override' { env['TEST_SELECTED_COMPILER'] = root + '/fake-bin/v' }
	args := match case_name {
		'help' { ['--help'] }
		'no-build' { ['--no-build'] }
		'compiler-override' { ['--no-build', '--v', root + '/fake-bin/v'] }
		'warm' {
			dependencies(root)!
			['--no-desktop']
		}
		else {
			os.rm(root + '/kernel/bin/vinix')!
			[]string{}
		}
	}
	result := hosttest.capture_in(['bash', root + '/scripts/run-desktop-aarch64.sh', ...args], '', 10, env, root)!
	assert result.code == 0, result.stdout + result.stderr
	events := os.read_file(root + '/events') or { '' }
	expected := match case_name {
		'help' { '' }
		'no-build', 'compiler-override' { 'prune\nfirmware\nboot\n' }
		'warm' { 'prune\ncompiler\nfirmware\nmake\nboot\n' }
		else { 'prune\ncompiler\nfirmware\ndeps\nmake\nprepare\ndesktop\nboot\n' }
	}
	assert events == expected, events
	if case_name == 'help' {
		assert result.stdout.contains('Usage:') && !os.exists(root + '/boot-image')
	} else {
		assert result.stdout.contains('fixture: reached QEMU runner')
	}
}

fn main() {
	if root := os.getenv_opt('VINIX_BOOTSTRAP_FIXTURE_ROOT') {
		fake(root, os.file_name(os.args[0]))!
		return
	}
	for name in ['help', 'cold', 'warm', 'no-build', 'compiler-override'] { check(name)! }
	println('PASS native desktop launcher bootstrap checks')
}
