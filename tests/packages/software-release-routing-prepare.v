// SPDX-License-Identifier: GPL-2.0-or-later
// Refresh only the service executables in a copied fresh native fixture root.
module main

import crypto.sha256
import hwhost
import json2
import os

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn copy_tree(source string, destination string) ! {
	mut child := os.new_process('cp')
	defer { child.close() }
	child.set_args(['-Rp', source, destination])
	child.wait()
	if child.code != 0 { return error('cannot copy ' + source) }
}

fn prepare() ! {
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') {
			return error('use --arch=aarch64|x86_64 --rootfs=FRESH_ROOT --out=NEW_DIRECTORY')
		}
		options[argument.all_before('=')] = argument.all_after('=')
	}
	arch := options['--arch'] or { return error('--arch is required') }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	input := os.real_path(options['--rootfs'] or { return error('--rootfs is required') })
	out := os.abs_path(options['--out'] or { return error('--out is required') })
	if !os.is_dir(input) || os.exists(input + '/var/lib/vinix-packages/state.json') ||
		os.exists(out) { return error('requires a fresh root and new output directory') }
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	os.mkdir_all(out + '/source/tools')!
	copy_tree(input, out + '/root')!
	for name in ['tools/packages', 'tools/accounts', 'desktop', 'compat'] {
		copy_tree(root + '/' + name, out + '/source/' + name)!
	}
	os.cp(@FILE, out + '/prepare.v')!
	mut inputs := map[string]string{}
	for path in os.walk_ext(out + '/source', '') {
		if os.is_file(path) { inputs[path[out.len + 1..]] = digest(path)! }
	}
	inputs['compiler'] = digest(host.v)!
	inputs['prepare.v'] = digest(@FILE)!
	cc := os.getenv_opt(if arch == 'aarch64' { 'CC_AARCH64' } else { 'CC_AMD64' }) or {
		return error('set the selected cross compiler explicitly')
	}
	inputs['cross-compiler'] = digest(os.find_abs_path_of_executable(cc)!)!
	os.write_file(out + '/inputs-before.json', json2.encode(inputs) + '\n')!
	frozen := hwhost.Host{ ...host, root: out + '/source' }
	programs := {
		'tools/packages/main.v':  'usr/bin/vinix-package'
		'tools/accounts/authd.v': 'usr/sbin/vinix-authd'
		'tools/accounts/account.v': 'usr/sbin/vinix-account'
		'tools/accounts/session.v': 'usr/sbin/vinix-session'
		'desktop/services/session/main.v': 'usr/bin/vinix-session'
	}
	mut outputs := map[string]string{}
	for source, target in programs {
		name := os.file_name(target)
		binary := hwhost.build_program_with_flags(frozen, out + '/source/' + source, out + '/build/' + target.replace('/', '-'),
			name, ['.', 'tools/accounts'], ['-enable-globals'])!
		os.cp(binary, out + '/root/' + target)!
		os.chmod(out + '/root/' + target, 0o755)!
		outputs[target] = digest(binary)!
	}
	for name, expected in inputs {
		path := if name == 'compiler' { host.v } else if name == 'cross-compiler' { cc } else {
			out + '/' + name
		}
		if digest(path)! != expected { return error('input changed during build: ' + name) }
	}
	os.write_file(out + '/inputs-after.json', json2.encode(inputs) + '\n')!
	os.write_file(out + '/outputs.json', json2.encode(outputs) + '\n')!
	println('SOFTWARE RELEASE ROUTING prepared current services ' + arch + ' PASS')
}

fn main() {
	prepare() or { eprintln(err); exit(1) }
}
