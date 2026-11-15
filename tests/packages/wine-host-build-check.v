// SPDX-License-Identifier: GPL-2.0-or-later
// Reseal only private copies; every case must refuse at its named check.
module main

import os
import json2
import tests.packages.winesource
import tests.packages.winecsource
import tests.packages.winehostimages

$if macos {
	#include <sys/clonefile.h>
	fn C.clonefile(&char, &char, i32) i32
}

struct Proof {
mut:
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
fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }

fn clone(source string, destination string) ! {
	os.mkdir_all(destination)!
	for path in os.walk_ext(source, '', hidden: true) {
		if os.lstat(path)!.get_filetype() != .regular { return error('host fixture must contain ordinary files') }
		to := destination + path[source.len..]
		os.mkdir_all(os.dir(to))!
		mut copied := false
		$if macos { copied = C.clonefile(path.str, to.str, 0) == 0 }
		if !copied { os.cp(path, to)! }
	}
}

fn invoke(tool string, directory string, log string) !(int, string) {
	mut child := os.new_process(tool)
	defer { child.close() }
	child.set_args(['check', directory]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	os.write_file(log, text)!
	return child.code, text
}

fn entry(directory string, role string, log string) ! {
	mut child := os.new_process(directory + '/program')
	defer { child.close() }
	child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': child.code}))!
	expected := match role {
		'fixture' { 'WINE HOST BUILD FIXTURE PASS\n' }
		'controller' { 'usage: wine-native-check ' }
		'producer' { 'usage: wine-build ' }
		else { return error('unsupported host entry role') }
	}
	if child.code != (if role == 'fixture' { 0 } else { 1 }) || !text.starts_with(expected) {
		return error('built host executable entry behavior differs: ' + role)
	}
}

fn check() ! {
	if os.args.len !in [4, 6] { return error('usage: CHECK HOST_BUILDER FIXTURE_BUILD FRESH_OUTPUT [CONTROLLER_BUILD PRODUCER_BUILD]') }
	tool := os.real_path(os.args[1]); original := os.real_path(os.args[2]); out := os.abs_path(os.args[3])
	if os.exists(out) || os.is_link(out) { return error('fresh host control output required') }
	os.mkdir_all(out)!
	code, _ := invoke(tool, original, out + '/baseline.log')!
	if code != 0 { return error('host baseline refused') }
	clone(original, out + '/copied')!
	copied_code, _ := invoke(tool, out + '/copied', out + '/copied.log')!
	if copied_code != 0 { return error('host copied baseline refused') }
	entry(original, 'fixture', out + '/fixture-entry.log')!
	if os.args.len == 6 {
		for index, role in ['controller', 'producer'] {
			directory := os.real_path(os.args[index + 4])
			status, _ := invoke(tool, directory, out + '/' + role + '-admission.log')!
			if status != 0 { return error('real host build admission failed: ' + role) }
			entry(directory, role, out + '/' + role + '-entry.log')!
		}
	}
	mut passed := []string{}
	for name in ['omitted-import', 'v-environment', 'c-environment', 'c-observation', 'c-argv', 'linked-receipt',
		'input-blob', 'omitted-image', 'binary-mode', 'format', 'v-argv', 'translation-unit', 'scope'] {
		dir := out + '/' + name
		clone(original, dir)!
		mut proof := json2.decode[Proof](os.read_file(dir + '/host-build.json')!)!
		mut changed := []string{}
		mut expected := ''
		if name == 'omitted-import' || name == 'omitted-image' {
			mut before := read_map(dir + '/v-inputs-before.json')!
			mut path := proof.root + '/tests/packages/winehostfixture/token.v'
			if name == 'omitted-image' {
				images := winehostimages.inputs(original + '/logs')!
				mut paths := images.keys(); paths.sort()
				selected := paths.filter(it !in before)
				if selected.len == 0 { return error('host image omission fixture is empty') }
				path = selected[0]
			} else {
				if path !in before { return error('hidden host import was not captured') }
				before.delete(path)
				os.write_file(dir + '/v-inputs-before.json', json2.encode(before))!
				changed << 'v-inputs-before.json'
			}
			proof.inputs.delete(path); proof.blobs.delete(path)
			for file in ['inputs.json', 'inputs-after.json'] { os.write_file(dir + '/' + file, json2.encode(proof.inputs))!; changed << file }
			expected = if name == 'omitted-import' { 'compiler source input is absent or changed' } else { 'host observed input is absent or changed' }
		} else if name == 'v-environment' || name == 'c-environment' {
			file := 'logs/' + if name == 'v-environment' { 'v.log.environment.json' } else { 'cc.log.environment.json' }
			mut env := read_map(dir + '/' + file)!
			env[if name == 'v-environment' { 'VFLAGS' } else { 'CPATH' }] = '/unrecorded'
			os.write_file(dir + '/' + file, json2.encode(env))!; changed << file
			expected = 'host tool environment differs'
		} else if name == 'c-observation' {
			before := json2.decode[winecsource.Proof](os.read_file(dir + '/c-inputs-before.json')!)!
			if before.includes.len < 2 { return error('host C fixture needs multiple includes') }
			for file in ['c-inputs-before.json', 'c-inputs-verified.json'] {
				os.write_file(dir + '/' + file, json2.encode(winecsource.Proof{sources: before.sources, includes: before.includes[1..]}))!; changed << file
			}
			expected = 'C closure include observations differ'
		} else if name == 'c-argv' || name == 'v-argv' {
			for file in if name == 'c-argv' { ['logs/cc.log.argv.json', 'logs/c-discover.log.argv.json'] } else { ['logs/v.log.argv.json'] } {
				mut args := json2.decode[[]string](os.read_file(dir + '/' + file)!)!
				args.insert(if file.contains('c-discover') { 3 } else if name == 'c-argv' { 2 } else { 1 }, '-DUNRECORDED')
				os.write_file(dir + '/' + file, json2.encode(args))!; changed << file
			}
			expected = if name == 'c-argv' { 'host C command differs' } else { 'host V command differs' }
		} else if name == 'linked-receipt' {
			file := dir + '/logs/v-host-images-before.json'
			os.rename(file, file + '-original')!; os.symlink(file + '-original', file)!
			expected = 'host image evidence must be a bounded ordinary file'
		} else if name == 'input-blob' {
			file := proof.blobs[proof.root + '/tests/packages/winehostfixture/token.v']
			if file == '' { return error('host blob fixture is missing') }
			os.write_file(dir + '/' + file, 'changed private input bytes')!
			expected = 'host selected input bytes differ'
		} else if name == 'binary-mode' {
			os.chmod(dir + '/program', 0o644)!
			expected = 'host executable mode differs'
		} else if name == 'format' || name == 'scope' {
			if name == 'format' { proof.format = 0 } else { proof.scope = 'complete hermetic admission' }
			expected = 'host build declaration differs'
		} else if name == 'translation-unit' {
			os.write_file(dir + '/program.c', os.read_file(dir + '/program.c')! + '\n/* resealed changed C */\n')!
			changed << 'program.c'
			expected = 'host translation unit output differs'
		}
		for file in changed { proof.outputs[file] = digest(dir + '/' + file)! }
		os.write_file(dir + '/host-build.json', json2.encode(proof))!
		status, text := invoke(tool, dir, out + '/' + name + '.log')!
		if status == 0 || !text.contains(expected) { return error('host control did not refuse at its named check: ' + name) }
		passed << name
	}
	os.write_file(out + '/result.json', json2.encode(passed) + '\n')!
	println('WINE HOST BUILD CONTROLS PASS real baseline copied baseline thirteen exact refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
