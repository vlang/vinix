// SPDX-License-Identifier: GPL-2.0-or-later
// Selected host V/C inputs only. Mach-O linked-library closure remains open.
module main

import os
import json2
import crypto.sha256
import tests.packages.winesource
import tests.packages.wineheaders
import tests.packages.winecsource
import tests.packages.winehostimages

$if macos {
	#include <sys/clonefile.h>
	fn C.clonefile(&char, &char, i32) i32
}

const clang = '/opt/homebrew/opt/llvm/bin/clang'
const scope = 'selected host V/C sources, resource headers and observed tool images; macOS linked libraries, system loader/cache and hermetic build admission remain unqualified'

struct Proof {
	format int
	scope string
	role string
	root string
	directory string
	compiler string
	builder string
	sdk string
	inputs map[string]string
	outputs map[string]string
	blobs map[string]string
}

fn digest(path string) !string { return winesource.file_digest(path) }

fn record(path string) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size < 1 || st.size > 16 * 1024 * 1024 { return error('host build evidence must be bounded and ordinary') }
	return os.read_file(path)
}

fn source(root string, role string) !string {
	return root + '/' + match role {
		'fixture' { 'tests/packages/wine-host-build-fixture/main.v' }
		'controller' { 'tests/packages/wine-native-check.v' }
		'producer' { 'tools/packages/wine-build.v' }
		else { return error('unsupported host build role') }
	}
}

fn v_command(root string, directory string, tool string, role string) ![]string {
	return [tool, '-backend', 'c', '-prod', '-os', 'macos', '-arch', 'arm64', '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-enable-globals', '-path', '@vlib|' + root + '|' + root + '/tools/packages|' + root + '/tests/hardware-platform|@vmodules',
		'-o', directory + '/program.c', source(root, role)!]
}

fn selected_sdk() !string {
	path := os.real_path('/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk')
	if !os.is_dir(path + '/usr/include') || !os.is_file(path + '/SDKSettings.json') { return error('selected host SDK is unavailable') }
	return path
}

fn c_command(directory string, resource string, sdk string) []string {
	return [clang, '-arch', 'arm64', '-isysroot', sdk, '-O2', '-w', '-fno-lto', '-Wno-error=incompatible-pointer-types', '-resource-dir=' + resource,
		directory + '/program.c', directory + '/runtime.c', '-lm', '-lpthread', '-o', directory + '/program']
}

fn artifacts() []string {
	mut names := ['program', 'program.c', 'runtime.c', 'v-inputs-before.json', 'inputs.json', 'inputs-after.json', 'sources-before.txt', 'sources-built.txt',
		'clang-headers.json', 'c-inputs-before.json', 'c-inputs-verified.json']
	for name in ['discover.log', 'v.log', 'clang-resource.log', 'c-discover.log', 'cc.log'] { names << ['logs/' + name, 'logs/' + name + '.argv.json'] }
	for name in [...winehostimages.v_artifacts(), ...winehostimages.c_artifacts()] { names << 'logs/' + name }
	return names
}

fn verify_self() ! {
	$if prod {} $else { return error('compile host builder with -prod') }
	for path, text in {
		@FILE: $embed_file('wine-host-build.v').to_string()
		os.dir(@FILE) + '/winesource/closure.v': $embed_file('winesource/closure.v').to_string()
		os.dir(@FILE) + '/wineheaders/headers.v': $embed_file('wineheaders/headers.v').to_string()
		os.dir(@FILE) + '/winecsource/closure.v': $embed_file('winecsource/closure.v').to_string()
		os.dir(@FILE) + '/winehostimages/images.v': $embed_file('winehostimages/images.v').to_string()
	} { if digest(path)! != sha256.hexhash(text) { return error('compiled host builder source differs: ' + path) } }
}

fn admit(directory string) ! {
	proof := json2.decode[Proof](record(directory + '/host-build.json')!)!
	root := os.real_path(os.dir(@FILE) + '/../..')
	if proof.format != 1 || proof.scope != scope || proof.root != root || !os.is_abs_path(proof.directory)
		|| proof.sdk != selected_sdk()! || os.real_path(proof.compiler) != proof.compiler { return error('host build declaration differs') }
	base := v_command(root, proof.directory, proof.compiler, proof.role)!
	mut discover := base.clone(); discover.insert(1, ['-print-watched-files', '-dump-files', proof.directory + '/sources-before.txt'])
	mut built := base.clone(); built.insert(1, ['-dump-files', proof.directory + '/sources-built.txt'])
	logs := directory + '/logs'
	if json2.decode[[]string](record(logs + '/discover.log.argv.json')!)! != discover
		|| json2.decode[[]string](record(logs + '/v.log.argv.json')!)! != built { return error('host V command differs') }
	if proof.inputs != json2.decode[map[string]string](record(directory + '/inputs.json')!)!
		|| proof.inputs != json2.decode[map[string]string](record(directory + '/inputs-after.json')!)! { return error('host input receipts differ') }
	v_before := json2.decode[map[string]string](record(directory + '/v-inputs-before.json')!)!
	winesource.admit(directory + '/sources-before.txt', directory + '/sources-built.txt', v_before)!
	for path, hash in v_before { if path !in proof.inputs || proof.inputs[path] != hash { return error('host V input pin differs') } }
	winehostimages.admit_v(logs, proof.directory + '/logs', proof.compiler, proof.inputs)!
	wineheaders.admit_build(directory, logs, proof.inputs)!
	winecsource.admit(directory, logs)!
	winehostimages.admit_c(logs, proof.directory + '/logs')!
	for selected in [winecsource.inputs(directory)!, winehostimages.inputs(logs)!, winehostimages.v_inputs(logs)!] {
		for path, hash in selected {
			if path !in proof.inputs || proof.inputs[path] != hash { return error('host observed input is absent or changed') }
		}
	}
	resource := wineheaders.selection(record(logs + '/clang-resource.log')!)!
	mut expected_cc := c_command(proof.directory, resource, proof.sdk); expected_cc.insert(1, '-H')
	if json2.decode[[]string](record(logs + '/cc.log.argv.json')!)! != expected_cc { return error('host C command differs') }
	if os.real_path(proof.builder) != proof.builder || os.lstat(proof.builder)!.get_filetype() != .regular { return error('host builder identity differs') }
	for path in [proof.compiler, proof.builder, clang, proof.sdk + '/SDKSettings.json', source(root, proof.role)!, @FILE, os.dir(@FILE) + '/winehostimages/images.v',
		os.dir(@FILE) + '/winesource/closure.v', os.dir(@FILE) + '/wineheaders/headers.v', os.dir(@FILE) + '/winecsource/closure.v'] {
		if path !in proof.inputs { return error('host required input is missing') }
	}
	if proof.inputs.len != proof.blobs.len { return error('host retained input map differs') }
	for path, hash in proof.inputs {
		if digest(path)! != hash || proof.blobs[path] != 'input-blobs/' + hash
			|| os.lstat(directory + '/' + proof.blobs[path])!.get_filetype() != .regular
			|| digest(directory + '/' + proof.blobs[path])! != hash { return error('host selected input bytes differ') }
	}
	names := artifacts()
	if proof.outputs.len != names.len { return error('host output inventory differs') }
	for name in names {
		if name !in proof.outputs || os.lstat(directory + '/' + name)!.get_filetype() != .regular
			|| digest(directory + '/' + name)! != proof.outputs[name] { return error('host output bytes differ: ' + name) }
	}
	for name in ['program.c', 'runtime.c'] {
		if proof.outputs[name] != proof.inputs[proof.directory + '/' + name] { return error('host translation unit output differs') }
	}
	if u32(os.lstat(directory + '/program')!.mode) & 0o7777 != 0o755 { return error('host executable mode differs') }
	bytes := os.read_bytes(directory + '/program')!
	if bytes.len < 32 || bytes[..8] != [u8(0xcf), 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1] || bytes[12..16] != [u8(2), 0, 0, 0] {
		return error('host output must be an arm64 Mach-O executable')
	}
}

fn build(role string, compiler string, requested string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	directory := os.real_path(os.dir(os.abs_path(requested))) + '/' + os.file_name(requested)
	tool := os.real_path(compiler)
	sdk := selected_sdk()!
	if os.exists(directory) || os.is_link(directory) { return error('fresh host build output required') }
	base := v_command(root, directory, tool, role)!
	os.mkdir_all(directory + '/logs')!
	os.chmod(directory, 0o700)!
	mut inputs := map[string]string{}
	for path in [tool, clang, sdk + '/SDKSettings.json', source(root, role)!, @FILE, os.real_path(os.executable()), os.dir(@FILE) + '/winehostimages/images.v',
		os.dir(@FILE) + '/winesource/closure.v', os.dir(@FILE) + '/wineheaders/headers.v', os.dir(@FILE) + '/winecsource/closure.v'] {
		inputs[path] = digest(path)!
	}
	mut discover := base.clone(); discover.insert(1, ['-print-watched-files', '-dump-files', directory + '/sources-before.txt'])
	winehostimages.invoke_v(discover, directory, directory + '/logs/discover.log')!
	winesource.capture(directory + '/sources-before.txt', mut inputs)!
	resource := wineheaders.selection(winehostimages.invoke([clang, '-print-resource-dir'], directory, directory + '/logs/clang-resource.log')!)!
	headers := wineheaders.capture(resource + '/include', mut inputs)!
	os.write_file(directory + '/clang-headers.json', json2.encode(headers) + '\n')!
	os.write_file(directory + '/v-inputs-before.json', json2.encode(inputs) + '\n')!
	mut command := base.clone(); command.insert(1, ['-dump-files', directory + '/sources-built.txt'])
	winehostimages.invoke_v(command, directory, directory + '/logs/v.log')!
	winesource.admit(directory + '/sources-before.txt', directory + '/sources-built.txt', inputs)!
	os.write_file(directory + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		os.dir(tool) + '/vlib/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + os.dir(tool) + '/vlib/sync/thread_helper.h"\n')!
	winecsource.build(c_command(directory, resource, sdk), directory, directory + '/logs')!
	os.chmod(directory + '/program', 0o755)!
	// Capture actual C targets and selected host images as well as parsed V files.
	for selected in [winecsource.inputs(directory)!, winehostimages.inputs(directory + '/logs')!, winehostimages.v_inputs(directory + '/logs')!] {
		for path, hash in selected {
			if path in inputs && inputs[path] != hash { return error('host selected input changed between phases') }
			inputs[path] = hash
		}
	}
	os.write_file(directory + '/inputs.json', json2.encode(inputs) + '\n')!
	os.mkdir_all(directory + '/input-blobs')!
	mut blobs := map[string]string{}
	for path, hash in inputs {
		if digest(path)! != hash { return error('host input changed during build') }
		stored := 'input-blobs/' + hash
		if !os.exists(directory + '/' + stored) {
			mut copied := false
			resolved := os.real_path(path)
			$if macos { copied = C.clonefile(resolved.str, (directory + '/' + stored).str, 0) == 0 }
			if !copied { os.cp(path, directory + '/' + stored)! }
		}
		blobs[path] = stored
	}
	os.write_file(directory + '/inputs-after.json', json2.encode(inputs) + '\n')!
	mut outputs := map[string]string{}
	for name in artifacts() { outputs[name] = digest(directory + '/' + name)! }
	os.write_file(directory + '/host-build.json', json2.encode(Proof{format: 1, scope: scope, role: role, root: root, directory: directory, compiler: tool, builder: os.real_path(os.executable()), sdk: sdk, inputs: inputs, outputs: outputs, blobs: blobs}) + '\n')!
	admit(directory)!
	println('WINE HOST BUILD PASS ' + role + ': ' + directory + '/program')
}

fn main() {
	verify_self() or { eprintln(err); exit(1) }
	if os.args.len == 3 && os.args[1] == 'check' { admit(os.real_path(os.args[2])) or { eprintln(err); exit(1) }; println('WINE HOST BUILD ADMISSION PASS'); return }
	if os.args.len != 5 || os.args[1] != 'build' { eprintln('usage: HOST_BUILD build ROLE V FRESH_OUTPUT | check BUILD'); exit(1) }
	build(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
}
