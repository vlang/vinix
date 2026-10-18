// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tests.packages.elffixture

// A compiler substitute for staging orchestration tests. Structural ELF output
// is never executed. All inputs/outputs and fault mutations belong to the test.
fn main() {
	args := os.args[1..]
	mut output := ''
	for i in 0 .. args.len - 1 { if args[i] == '-o' { output = args[i + 1] } }
	assert output != ''
	name := os.file_name(output).all_before_last('.c')
	names := ['vinix-package', 'vinix-session', 'vinix-linux-runner']
	index := names.index(name)
	assert index >= 0
	role := if output.ends_with('.c') { 'v' } else { 'c' }
	work := os.getenv('VINIX_IMAGE_TOOL_CLI_WORK')
	fault := os.getenv('VINIX_IMAGE_TOOL_FAULT')
	mut log := os.open_append(work + '/calls.jsonl') or { panic(err) }
	log.writeln(json2.encode(os.args)) or { panic(err) }; log.close()
	if fault == role + '-' + index.str() { eprintln('injected compiler failure: ' + role + ' ' + name); exit(37) }
	if role == 'v' {
		architecture := if 'arm64' in args { 'aarch64' } else { 'x86_64' }
		os.write_file(output, architecture) or { panic(err) }
		if fault == 'workspace-replaced' {
			directory := os.dir(output)
			os.rename(directory, work + '/saved-workspace') or { panic(err) }
			os.mkdir(directory) or { panic(err) }; os.write_file(directory + '/keep', 'replacement compiler workspace') or { panic(err) }
			os.write_file(work + '/replacement-path', directory) or { panic(err) }
		}
		if fault == 'root-replaced' {
			os.rename(work + '/image', work + '/saved-image') or { panic(err) }
			os.mkdir(work + '/image') or { panic(err) }; os.write_file(work + '/image/keep', 'replacement image') or { panic(err) }
		}
		return
	}
	mut architecture := os.read_file(output + '.c') or { panic(err) }
	if fault == 'wrong-' + index.str() { architecture = if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' } }
	mut data := elffixture.image(architecture, 'static'); data[400] = u8(index + 1)
	os.write_file_array(output, data) or { panic(err) }; os.chmod(output, 0o755) or { panic(err) }
	if fault == 'corrupt-previous' && index == 2 { os.write_file(os.dir(output) + '/vinix-package', 'late invalid compiler output') or { panic(err) } }
}
