// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(root string, label string, args []string) !string {
	executable := os.find_abs_path_of_executable(args[0])!
	pin := hash(executable)!
	result := os.exec(args)
	os.write_file(root + '/' + label + '.log', result.output)!
	os.write_file(root + '/' + label + '-command.json', json2.encode({
		'argv':              json2.Any(args)
		'executable':        json2.Any(executable)
		'executable_sha256': json2.Any(pin)
		'exit_code':         json2.Any(result.exit_code)
	}, prettify: true) + '\n')!
	if hash(executable)! != pin { return error('tool changed during command') }
	if result.exit_code != 0 { return error(label + ' failed; retained command and log') }
	return result.output
}

fn constants_and_condition(source string) !(string, string) {
	mut constants := ''
	for name in ['msg_cmsg_cloexec', 'msg_nosignal'] {
		lines := source.split_into_lines().filter(it.starts_with('const ' + name + ' = '))
		if lines.len != 1 { return error('expected unique production constant ' + name) }
		constants += lines[0] + '\n'
	}
	marker := 'fn (mut this UnixSocket) recvmsg('
	if source.count(marker) != 1 { return error('expected unique production recvmsg') }
	function := source.all_after(marker)
	mut conditions := []string{}
	for line in function.split_into_lines() {
		if line.trim_space().starts_with('if flags & ') {
			conditions << line.trim_space().all_after('if ').all_before_last(' {')
			break
		}
	}
	if conditions.len != 1 || !conditions[0].contains('msg_cmsg_cloexec')
		|| !function.all_after('if ' + conditions[0]).starts_with(' {\n\t\terrno.set(errno.eopnotsupp)\n\t\treturn none\n\t}') {
		return error('unsupported flag rejection shape changed; review extraction')
	}
	return constants, conditions[0]
}

fn flag_fixture(constants string, condition string) string {
	return 'module main\n' + constants + '\nfn rejected(flags int) bool { return ' + condition + ' }\n' +
		'fn main() {\n' +
		'\tfor flags in [0, 0x4000, 0x40000000, 0x40004000] { if rejected(flags) { eprintln("accepted flag rejected"); exit(1) } }\n' +
		'\tfor bit in 0 .. 32 {\n' +
		'\t\tmask := int(u32(1) << bit)\n' +
		'\t\tif mask == 0x4000 || mask == 0x40000000 { continue }\n' +
		'\t\tfor accepted in [0, 0x4000, 0x40000000, 0x40004000] { if !rejected(mask | accepted) { eprintln("unsupported flag accepted"); exit(1) } }\n' +
		'\t}\n\tprintln("UNIX-RECVMSG-MASK-PASS accepted=4 rejected=120")\n}\n'
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('unexpected artifact file type') }
		}
	}
}

fn run() ! {
	if os.args.len != 4 { return error('usage: build REPO V_COMPILER FRESH_EXTERNAL_ROOT') }
	repo, compiler, root := os.real_path(os.args[1]), os.real_path(os.args[2]), os.abs_path(os.args[3])
	if os.exists(root) || os.is_link(root) || root == repo || root.starts_with(repo + '/') {
		return error('fresh external artifact root required')
	}
	os.mkdir_all(root)!
	if os.real_path(root) != root { return error('canonical artifact root required') }
	os.chdir(repo)!
	revision := command(root, 'revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	source := repo + '/tests/unix-recvmsg-flags'
	listing := command(root, 'guest-sources', [compiler, '-os', 'linux', '-arch', 'arm64', '-gc',
		'none', '-print-v-files', source + '/guest.v'])!
	mut inputs := listing.split_into_lines().filter(it.ends_with('.v'))
	for path in [source + '/build.v', source + '/README.md', repo + '/kernel/socket/unix/unix.v'] {
		if path !in inputs { inputs << path }
	}
	mut pins := map[string]string{}
	for path in inputs {
		if os.lstat(path)!.get_filetype() != .regular { return error('regular source required') }
		pins[path] = hash(path)!
		target := root + '/sources' + path
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		if hash(target)! != pins[path]! { return error('source changed during freeze') }
	}
	os.write_file(root + '/source-inputs.json', json2.encode(pins, prettify: true) + '\n')!
	kernel := os.read_file(root + '/sources' + repo + '/kernel/socket/unix/unix.v')!
	constants, condition := constants_and_condition(kernel)!
	fixture := root + '/mask.v'
	os.write_file(fixture, flag_fixture(constants, condition))!
	command(root, 'build-mask', [compiler, '-cc', '/usr/bin/cc', '-o', root + '/mask', fixture])!
	command(root, 'run-mask', [root + '/mask'])!
	// The previous implementation must fail the same extracted checks.
	os.write_file(root + '/old-mask.v', flag_fixture(constants, 'flags & ~msg_cmsg_cloexec != 0'))!
	command(root, 'build-old-mask', [compiler, '-cc', '/usr/bin/cc', '-o', root + '/old-mask',
		root + '/old-mask.v'])!
	old := os.exec([root + '/old-mask'])
	os.write_file(root + '/run-old-mask.log', old.output)!
	if old.exit_code != 1 || !old.output.contains('accepted flag rejected') {
		return error('old-mask negative control did not detect regression')
	}
	os.write_file(root + '/run-old-mask-command.json', json2.encode({
		'argv':             json2.Any([root + '/old-mask'])
		'exit_code':        json2.Any(old.exit_code)
		'expected_failure': json2.Any(true)
	}, prettify: true) + '\n')!
	frozen := root + '/sources' + source + '/guest.v'
	command(root, 'build-guest', [compiler, '-gc', 'none', '-os', 'linux', '-arch', 'arm64', '-cc',
		'aarch64-linux-musl-gcc', '-cflags', '-static', '-showcc', '-o', root + '/guest', frozen])!
	elf := command(root, 'guest-elf', ['aarch64-linux-musl-readelf', '-h', '-l', '-d', root + '/guest'])!
	if !elf.contains('AArch64') || elf.contains('INTERP') || elf.contains('(NEEDED)') {
		return error('expected static ARM64 guest executable')
	}
	for path, pin in pins {
		if hash(path)! != pin || hash(root + '/sources' + path)! != pin {
			return error('source changed during build')
		}
	}
	os.write_file(root + '/build.json', json2.encode({
		'format':                    json2.Any(1)
		'source_revision':           json2.Any(revision)
		'kernel_source_sha256':      json2.Any(pins[repo + '/kernel/socket/unix/unix.v']!)
		'guest_sha256':              json2.Any(hash(root + '/guest')!)
		'guest_executed':            json2.Any(false)
		'production_mask_cases':     json2.Any(124)
		'old_mask_negative_control': json2.Any(true)
		'coverage':                  json2.Any('host extraction checks flag rejection; guest executable requires Vinix syscall execution')
	}, prettify: true) + '\n')!
	mut artifacts := map[string]string{}
	inventory(root, '', mut artifacts)!
	os.write_file(root + '/sha256.json', json2.encode(artifacts, prettify: true) + '\n')!
	println('UNIX-RECVMSG-BUILD-PASS root=' + root + ' manifest_sha256=' + hash(root + '/sha256.json')!)
}

run() or {
	eprintln(err)
	exit(1)
}
