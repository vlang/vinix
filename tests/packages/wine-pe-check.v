// SPDX-License-Identifier: GPL-2.0-or-later
// Retain the real V -> MinGW Win64 probe and its observed build inputs.
module main

import crypto.sha256
import encoding.binary
import json2
import os

struct PeInput {
	kind string
	target string
	sha256 string
}

struct PeBuild {
	format int = 1
	scope string = 'local real Win64 probe producer; input pins are not a hermetic build or a Wine execution result'
	compiler string
	mingw_root string
	source string
	environment map[string]string
	inputs map[string]PeInput
	outputs map[string]string
	commands [][]string
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut sum := []u8{len: 32}
	defer {
		unsafe { buffer.free(); sum.free(); hash.free(); free(hash) }
	}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	hash.checksum_into(mut sum)
	return sum.hex()
}

// Do not follow directory links: their real targets must be within the same
// inventoried root, where the ordinary directory walk already visits them.
fn inventory(path string, root string, mut inputs map[string]PeInput) ! {
	if os.is_link(path) {
		target := os.real_path(path)
		if target != root && !target.starts_with(root + '/') {
			return error('build input symlink escapes its inventoried root: ' + path)
		}
		if !os.exists(target) { return error('dangling build input: ' + path) }
		inputs[path] = PeInput{kind: 'symlink', target: os.readlink(path)!}
		return
	}
	if os.is_dir(path) {
		inputs[path] = PeInput{kind: 'directory'}
		mut names := os.ls(path)!
		names.sort()
		for name in names { inventory(path + '/' + name, root, mut inputs)! }
		return
	}
	if !os.is_file(path) { return error('unsupported build input: ' + path) }
	inputs[path] = PeInput{kind: 'file', sha256: digest(path)!}
}

fn capture(roots []string, files []string) !map[string]PeInput {
	mut inputs := map[string]PeInput{}
	for root in roots { inventory(root, root, mut inputs)! }
	for path in files { inputs[path] = PeInput{kind: 'file', sha256: digest(path)!} }
	return inputs
}

fn invoke(argv []string, env map[string]string, work string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_environment(env)
	child.set_work_folder(work)
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	os.write_file(log, output)!
	if child.code != 0 { return error('Win64 producer command failed: ' + log) }
}

fn validate_pe(path string) ! {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	if bytes.len < 256 || bytes[0] != `M` || bytes[1] != `Z` {
		return error('Win64 output lacks its DOS header')
	}
	header := u64(binary.little_endian_u32(bytes[60..64]))
	if header > u64(bytes.len) - 94 { return error('Win64 PE header is outside the file') }
	start := int(header)
	if bytes[start..start + 4] != [u8(`P`), `E`, 0, 0]
		|| binary.little_endian_u16(bytes[start + 4..start + 6]) != 0x8664
		|| binary.little_endian_u16(bytes[start + 20..start + 22]) < 70
		|| binary.little_endian_u16(bytes[start + 22..start + 24]) & 0x2002 != 2
		|| binary.little_endian_u16(bytes[start + 24..start + 26]) != 0x20b
		|| binary.little_endian_u16(bytes[start + 92..start + 94]) != 3 {
		return error('output must be an executable AMD64 PE32+ Windows console program')
	}
}

fn check() ! {
	$if prod {} $else { return error('compile wine-pe-check with -prod to bind its source') }
	if digest(@FILE)! != sha256.hexhash($embed_file('wine-pe-check.v').to_string()) {
		return error('Win64 producer source differs from its executable')
	}
	if os.args.len != 6 { return error('usage: wine-pe-check V MINGW_ROOT PROGRAM_V NEW_OUTPUT --local-qualification-only') }
	v := os.real_path(os.args[1])
	mingw := os.real_path(os.args[2])
	source := os.real_path(os.args[3])
	requested := os.abs_path(os.args[4])
	// The final literal makes the local, non-redistribution scope explicit.
	if os.args[5] != '--local-qualification-only' { return error('local qualification acknowledgement required') }
	if os.exists(requested) || os.is_link(requested) { return error('Win64 producer requires a new output directory') }
	parent := os.real_path(os.dir(requested))
	if !os.is_dir(parent) { return error('Win64 output parent must already exist') }
	out := parent + '/' + os.file_name(requested)
	vroot := os.dir(v)
	gcc := mingw + '/bin/x86_64-w64-mingw32-gcc'
	objdump := mingw + '/bin/x86_64-w64-mingw32-objdump'
	roots := [vroot + '/vlib', vroot + '/thirdparty', mingw]
	files := [v, source, os.real_path(@FILE), os.real_path(os.executable())]
	for root in roots {
		if !os.is_dir(root) || out == root || out.starts_with(root + '/') {
			return error('invalid toolchain root or output inside an input tree: ' + root)
		}
	}
	if !os.is_file(gcc) || !os.is_file(objdump) { return error('MinGW AMD64 GCC and objdump are required') }
	inputs := capture(roots, files)!
	if inputs[os.real_path(@FILE)].sha256 != sha256.hexhash($embed_file('wine-pe-check.v').to_string()) {
		return error('Win64 producer source changed before input capture')
	}
	os.mkdir(out)!
	os.chmod(out, 0o700)!
	for name in ['tmp', 'home', 'modules']! { os.mkdir(out + '/' + name)! }
	os.cp(source, out + '/program.v')!
	os.cp(@FILE, out + '/producer.v')!
	os.write_file(out + '/inputs-before-build.json', json2.encode(inputs) + '\n')!
	env := {
		'PATH': mingw + '/bin:/usr/bin:/bin'
		'HOME': out + '/home'
		'TMPDIR': out + '/tmp'
		'VMODULES': out + '/modules'
		'LANG': 'C'
		'LC_ALL': 'C'
		'TZ': 'UTC'
		'SOURCE_DATE_EPOCH': '0'
		'VEXE': v
		'V_MACOS_V3_CALLER_VEXE': v
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_C_ERROR_BUG_REPORT_DISABLED': '1'
	}
	os.write_file(out + '/environment.json', json2.encode(env) + '\n')!
	cfile := out + '/program.c'
	pe := out + '/program.exe'
	commands := [
		[v, '-backend', 'c', '-prod', '-os', 'windows', '-arch', 'amd64', '-gc', 'none',
			'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib',
			'-o', cfile, out + '/program.v'],
		[gcc, '-v', '-O2', '-w', '-static', '-municode', '-Wl,--no-insert-timestamp',
			'-Wl,-Map,' + out + '/program.map', '-o', pe, cfile,
			vroot + '/vlib/builtin/core_windows.c', '-lws2_32', '-ladvapi32', '-lshell32'],
		[objdump, '-p', pe],
	]
	for index, argv in commands {
		name := ['v', 'cc', 'pe-headers'][index]
		invoke(argv, env, out, out + '/' + name + '.log')!
	}
	validate_pe(pe)!
	if capture(roots, files)! != inputs { return error('Win64 producer inputs changed during the build') }
	if digest(out + '/program.v')! != inputs[source].sha256 { return error('retained Win64 source differs') }
	if digest(out + '/producer.v')! != inputs[os.real_path(@FILE)].sha256 { return error('retained producer source differs') }
	os.write_file(out + '/inputs-verified.json', json2.encode(inputs) + '\n')!
	mut outputs := map[string]string{}
	for name in ['program.v', 'producer.v', 'program.c', 'program.exe', 'program.map', 'environment.json',
		'inputs-before-build.json', 'inputs-verified.json', 'v.log', 'v.log.argv.json',
		'cc.log', 'cc.log.argv.json', 'pe-headers.log', 'pe-headers.log.argv.json']! {
		outputs[name] = digest(out + '/' + name)!
	}
	os.write_file(out + '/proof.json', json2.encode(PeBuild{compiler: v, mingw_root: mingw,
		source: source, environment: env, inputs: inputs, outputs: outputs, commands: commands}) + '\n')!
	println('WINE real AMD64 PE32+ producer source/C/toolchain/argv pins PASS: ' + pe)
}

fn main() { check() or { eprintln(err); exit(1) } }
