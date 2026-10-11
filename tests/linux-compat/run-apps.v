// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct AppReceipt {
	architecture   string
	execution_path string
	cases          string
	inputs         map[string]string
	exit_code      int
}

fn copy_guest_tree(source string, destination string, relative string, mut manifest map[string]string) ! {
	// Guest absolute links refer to the guest root, never the host's /lib or
	// /bin. Preserve their literal targets instead of dereferencing them.
	if os.is_link(source) {
		target := os.readlink(source)!
		os.symlink(target, destination)!
		manifest[relative] = 'link:' + target
		return
	}
	mode := int(os.stat(source)!.mode & 0o7777)
	if os.is_dir(source) {
		os.mkdir_all(destination)!
		mut names := os.ls(source)!
		names.sort()
		for name in names {
			copy_guest_tree(source + '/' + name, destination + '/' + name, relative + '/' + name, mut manifest)!
		}
		os.chmod(destination, mode)!
		manifest[relative] = 'directory:' + mode.str()
		return
	}
	if !os.is_file(source) { return error('unsupported prepared-root node: ' + source) }
	bytes := os.read_bytes(source)!
	os.write_file_array(destination, bytes)!
	os.chmod(destination, mode)!
	manifest[relative] = 'file:' + mode.str() + ':' + sha256.sum(bytes).hex()
}

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--path', value: true, choices: ['native-aarch64', 'native-x86_64',
			'translated-x86_64', 'translated-i386'] },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--rootfs', value: true },
		hosttest.Option{ name: '--workloads', value: true },
		hosttest.Option{ name: '--runtime-probe', value: true },
		hosttest.Option{ name: '--runtime-libc', value: true, choices: ['musl', 'glibc'] },
		hosttest.Option{ name: '--cases', value: true },
		hosttest.Option{ name: '--timeout', value: true },
	], [], 'Usage: run-apps.v --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR --rootfs PREPARED-ROOT --workloads NATIVE-ELF --runtime-probe MATCHING-ELF [--path PATH] [--cases runtime,server]') or {
		eprintln(err.msg())
		exit(2)
	}
	for key in ['--arch', '--kernel-dir', '--state-dir', '--rootfs', '--workloads', '--runtime-probe'] {
		if !options.has(key) {
			eprintln('missing ' + key)
			exit(2)
		}
	}
	arch := options.value('--arch', '')
	path := options.value('--path', if arch == 'aarch64' {
		'native-aarch64'
	} else {
		'native-x86_64'
	})
	if (arch == 'aarch64' && path == 'native-x86_64') || (arch == 'x86_64' && path != 'native-x86_64') {
		eprintln('execution path does not match guest architecture')
		exit(2)
	}
	cases := options.value('--cases', 'runtime,server')
	for name in cases.split(',') {
		if name !in ['sqlite', 'media', 'office', 'chromium', 'firefox', 'go', 'java', 'v', 'server',
			'runtime', 'portal', 'games'] {
			eprintln('unknown case')
			exit(2)
		}
	}
	state := options.value('--state-dir', '')
	timeout := options.integer('--timeout', 300) or {
		eprintln(err.msg())
		exit(2)
	}
	if timeout <= 0 || os.exists(state) {
		eprintln('timeout must be positive and state directory fresh')
		exit(2)
	}
	rootfs := os.real_path(options.value('--rootfs', ''))
	if !os.is_dir(rootfs) || os.abs_path(state).starts_with(rootfs + '/') {
		eprintln('prepared root must be a directory outside the fresh state')
		exit(2)
	}
	mut inputs := map[string]string{}
	mut snapshots := map[string][]u8{}
	for kind in ['kernel', 'workloads', 'runtime-probe'] {
		file := if kind == 'kernel' {
			options.value('--kernel-dir', '') + '/bin/vinix'
		} else {
			options.value('--' + kind, '')
		}
		bytes := os.read_bytes(file) or {
			eprintln(err.msg())
			exit(2)
		}
		machine := if bytes.len >= 20 { int(bytes[18]) + (int(bytes[19]) << 8) } else { 0 }
		expected_machine := if kind == 'runtime-probe' && path == 'translated-i386' {
			3
		} else if kind == 'runtime-probe' && path == 'translated-x86_64' {
			62
		} else if arch == 'aarch64' {
			183
		} else {
			62
		}
		expected_class := if expected_machine == 3 { 1 } else { 2 }
		if bytes.len < 20 || bytes[..4] != [u8(127), `E`, `L`, `F`] || bytes[4] != expected_class || bytes[5] != 1 || machine != expected_machine {
			eprintln('ELF architecture mismatch: ' + kind)
			exit(2)
		}
		inputs[kind] = sha256.sum(bytes).hex()
		snapshots[kind] = bytes
	}
	os.mkdir_all(state + '/kernel/bin') or {
		eprintln(err.msg())
		exit(1)
	}
	mut manifest := map[string]string{}
	copy_guest_tree(rootfs, state + '/rootfs', '', mut manifest) or {
		eprintln(err.msg())
		exit(1)
	}
	manifest_text := json2.encode(manifest, prettify: true) + '\n'
	os.write_file(state + '/rootfs-inputs.json', manifest_text) or {
		eprintln(err.msg())
		exit(1)
	}
	inputs['rootfs_manifest'] = sha256.sum(manifest_text.bytes()).hex()
	for dir in ['etc', 'usr/bin', 'usr/share/linux-compat'] {
		os.mkdir_all(state + '/rootfs/' + dir) or {
			eprintln(err.msg())
			exit(1)
		}
	}
	os.write_file(state + '/rootfs/etc/linux-compat-options', '--cases=' + cases + '\x00--path=' + path + '\x00--runtime-libc=' + options.value('--runtime-libc', 'musl') + '\x00') or {
		eprintln(err.msg())
		exit(1)
	}
	os.write_file_array(state + '/rootfs/usr/bin/linux-compat-workloads', snapshots['workloads']) or {
		eprintln(err.msg())
		exit(1)
	}
	os.write_file_array(state + '/rootfs/usr/share/linux-compat/runtime', snapshots['runtime-probe']) or {
		eprintln(err.msg())
		exit(1)
	}
	os.write_file_array(state + '/kernel/bin/vinix', snapshots['kernel']) or {
		eprintln(err.msg())
		exit(1)
	}
	for file in ['usr/bin/linux-compat-workloads', 'usr/share/linux-compat/runtime'] {
		os.chmod(state + '/rootfs/' + file, 0o755) or {
			eprintln(err.msg())
			exit(1)
		}
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	source := os.read_file(root + '/tests/linux-compat/appinitfixture/core.v') or {
		eprintln(err.msg())
		exit(1)
	}
	os.mkdir_all(state + '/sources/appinitfixture') or {
		eprintln(err.msg())
		exit(1)
	}
	os.write_file(state + '/sources/appinitfixture/core.v', source) or {
		eprintln(err.msg())
		exit(1)
	}
	inputs['init_source'] = sha256.sum(source.bytes()).hex()
	mut code := guesthost.guest(os.real_path(state + '/sources/appinitfixture/core.v'), '', os.real_path(state), os.real_path(state + '/kernel'), arch, ['LINUX APPLICATIONS: PASS'], ['LINUX APPLICATIONS FAIL'], false, true, timeout) or {
		eprintln(err.msg())
		1
	}
	serial := (os.read_file(state + '/serial.log') or { '' }).replace('\r', '')
	if serial.contains('LINUX APPLICATION REPORT BEGIN\n') && serial.contains('LINUX APPLICATION REPORT END') {
		report := serial.all_after('LINUX APPLICATION REPORT BEGIN\n').all_before('LINUX APPLICATION REPORT END').trim_space()
		json2.decode[json2.Any](report) or {
			eprintln('invalid guest report: ' + err.msg())
			code = 1
		}
		os.write_file(state + '/guest-report.json', report + '\n') or {
			eprintln(err.msg())
			exit(1)
		}
		inputs['guest_report'] = sha256.sum(report.bytes()).hex()
	} else {
		eprintln('guest did not publish an application report')
		code = 1
	}
	inputs['snapshot_kernel'] = sha256.sum(os.read_bytes(state + '/kernel/bin/vinix') or { []u8{} }).hex()
	os.write_file(state + '/application-inputs.json', json2.encode(AppReceipt{arch, path, cases, inputs, code},
		prettify: true
	)) or {
		eprintln(err.msg())
		exit(1)
	}
	exit(code)
}
