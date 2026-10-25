// SPDX-License-Identifier: GPL-2.0-or-later
// Stage the account service used by the ordinary graphical login path.
module main

import json2
import os
import stagecore
import crypto.sha256

fn file_digest(path string) !string {
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	return sha256.hexhash(unsafe { tos(data.data, data.len) })
}

fn build_input_paths(repository string, v string, compiler string) !map[string]string {
	mut paths := {
		'stager':         os.executable()
		'compiler-v':     v
		'compiler-c':     compiler
		'compiler-v.mod': os.dir(v) + '/v.mod'
		'stage-source':   @FILE
	}
	source_inputs(repository + '/tools/accounts', 'accounts/', mut paths)!
	source_inputs(repository + '/tools/packages', 'packages/', mut paths)!
	source_inputs(os.dir(v) + '/vlib', 'vlib/', mut paths)!
	source_inputs(os.dir(v) + '/thirdparty', 'thirdparty/', mut paths)!
	for name in os.ls(repository + '/tools/accounts/actions')! {
		paths['action/' + name] = repository + '/tools/accounts/actions/' + name
	}
	return paths
}

fn source_inputs(directory string, prefix string, mut paths map[string]string) ! {
	entries := os.ls(directory)!
	defer { unsafe { entries.free() } }
	for name in entries {
		path := directory + '/' + name
		defer { unsafe { path.free() } }
		if os.is_link(path) { continue }
		if os.is_dir(path) {
			source_inputs(path, prefix + name + '/', mut paths)!
			continue
		}
		if !name.ends_with('_test.v') && (name.ends_with('.v') || name.ends_with('.c') || name.ends_with('.h') || name.ends_with('.S') || name.ends_with('.o') || name.ends_with('.a')) {
			paths[prefix + name] = path.clone()
		}
	}
}

fn invoke(program string, arguments []string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.wait()
	if child.code != 0 { return error('${program} failed (${child.code})') }
}

fn stage() ! {
	mut architecture := ''
	mut staging := ''
	mut cc := []string{}
	mut include_session := false
	mut evidence := ''
	mut index := 1
	for index < os.args.len {
		if os.args[index] == '--include-session' {
			include_session = true
			index++
			continue
		}
		if index + 1 == os.args.len { return error('missing staging option value') }
		match os.args[index] {
			'--arch' { architecture = os.args[index + 1] }
			'--staging' { staging = os.abs_path(os.args[index + 1]) }
			'--cc-argv' { cc = json2.decode[[]string](os.args[index + 1])! }
			'--evidence' { evidence = os.abs_path(os.args[index + 1]) }
			else { return error('unknown account staging option: ' + os.args[index]) }
		}
		index += 2
	}
	if architecture !in ['aarch64', 'x86_64'] || staging == '' || staging == '/' || !os.is_dir(staging) {
		return error('use --arch aarch64|x86_64 --staging EXISTING_ROOT [--cc-argv JSON] [--include-session]')
	}
	mut installer := stagecore.open(staging)!
	defer { installer.close() }
	// Alpine ships shadow as 0640, while our account store requires every
	// password record to be private to its owner. Preserve the imported records
	// through the same checked atomic publication used for account executables.
	shadow := staging + '/etc/shadow'
	if os.exists(shadow) || os.is_link(shadow) {
		installer.put(shadow, 'etc/shadow', 0o600)!
	}
	if cc.len == 0 { cc = [architecture + '-linux-musl-gcc', '-w', '-Wno-error=incompatible-pointer-types'] }
	compiler := os.find_abs_path_of_executable(cc[0])!
	configured_v := os.getenv('V')
	v := os.find_abs_path_of_executable(if configured_v == '' { 'v' } else { configured_v })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	work := os.join_path(os.temp_dir(), 'vinix-accounts-${os.getpid()}')
	os.mkdir(work, mode: 0o700)!
	defer { os.rmdir_all(work) or {} }
	mut proof := stagecore.Installer{}
	defer { proof.close() }
	mut input_paths := map[string]string{}
	mut input_hashes := map[string]string{}
	mut outputs := map[string]string{}
	if evidence != '' {
		$if prod {
		} $else {
			return error('retained account evidence requires a -prod staging tool')
		}
		if file_digest(@FILE)! != sha256.hexhash($embed_file('stage.v').to_string()) {
			return error('account staging source differs from this executable')
		}
		info := os.lstat(evidence)!
		if info.mode & 0o170000 != 0o040000 || info.mode & 0o777 != 0o700 || (info.uid != 0 && info.uid != u32(C.geteuid())) || os.ls(evidence)!.len != 0 {
			return error('account evidence requires an empty private owned directory')
		}
		proof = stagecore.open(evidence)!
		input_paths = build_input_paths(repository, v, compiler)!
		for name, path in input_paths { input_hashes[name] = file_digest(path)! }
	}
	mut programs := ['authd', 'account', 'system', 'auth']
	if include_session { programs << 'session' }
	for program in programs {
		installer.check()!
		source := work + '/' + program + '.c'
		binary := work + '/' + program
		v_argv := ['-new-compiler', '-enable-globals', '-path',
			'@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts', '-gc', 'none',
			'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
			if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', source,
			repository + '/tools/accounts/' + program + '.v']
		c_argv := [...cc[1..], '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', source, '-o', binary,
			'-lm', '-lpthread']
		invoke(v, v_argv)!
		invoke(compiler, c_argv)!
		header := os.read_bytes(binary)!
		if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| int(header[18]) + (int(header[19]) << 8) != if architecture == 'aarch64' {
				183
			} else {
				62
			} {
			return error('compiler produced a wrong-architecture account executable')
		}
		installer.put(binary, 'usr/' + if program == 'auth' { 'bin' } else { 'sbin' } + '/vinix-' + program, 0o755)!
		if evidence != '' {
			proof.put(source, program + '/' + program + '.c', 0o644)!
			proof.put(binary, program + '/vinix-' + program, 0o755)!
			argv := work + '/argv.json'
			os.write_file(argv, json2.encode({
				'v': [v, ...v_argv]
				'c': [compiler, ...c_argv]
			}))!
			proof.put(argv, program + '/argv.json', 0o644)!
			for name in [program + '.c', 'vinix-' + program, 'argv.json'] {
				outputs[program + '/' + name] = file_digest(evidence + '/' + program + '/' + name)!
			}
		}
	}
	for action in os.ls(repository + '/tools/accounts/actions')! {
		installer.put(repository + '/tools/accounts/actions/' + action,
			'usr/share/vinix/actions/' + action, 0o644)!
		if evidence != '' {
			outputs['installed-action/' + action] = file_digest(staging + '/usr/share/vinix/actions/' + action)!
			if outputs['installed-action/' + action] != input_hashes['action/' + action] {
				return error('installed account action differs from its input: ' + action)
			}
			proof.put(repository + '/tools/accounts/actions/' + action,
				'installed-action/' + action, 0o644)!
		}
	}
	if evidence != '' {
		if build_input_paths(repository, v, compiler)! != input_paths {
			return error('account build input inventory changed')
		}
		for name, path in input_paths {
			if file_digest(path)! != input_hashes[name] {
				return error('account build input changed: ' + name)
			}
		}
		proof.check()!
		for name, text in {
			'inputs':      json2.encode(input_hashes)
			'input-paths': json2.encode(input_paths)
			'outputs':     json2.encode(outputs)
			'arguments':   json2.encode(os.args)
			'result':      json2.encode({
				'architecture': architecture
				'passed':       'true'
			})
		} {
			path := work + '/' + name + '.json'
			os.write_file(path, text)!
			proof.put(path, 'receipt/' + name + '.json', 0o644)!
		}
	}
	println('Staged account authentication and graphical login support (${architecture})')
}

fn main() {
	stage() or {
		eprintln('account staging: ${err}')
		exit(1)
	}
}
