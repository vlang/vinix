// SPDX-License-Identifier: GPL-2.0-or-later
// Reseal only private copies; every case must refuse at its named check.
module main

import os
import json2
import tests.packages.winesource
import tests.packages.winecsource
import tests.packages.winehostimages
import tests.packages.winedirclosure
import tests.packages.winemetaclosure
import tests.packages.winemetaimages

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

struct HostLink {
mut:
	format int
	recorded_directory string
	archive_sha256 string
	output_sha256 string
	linker string
	linker_sha256 string
	loads map[string]string
}

struct HostRead {
mut:
	format int
	recorded_directory string
	builder string
	archive_sha256 string
	output_sha256 string
	policy string
	directories []string
	metadata []string
	capabilities map[string]string
	loads map[string]string
	images []winehostimages.Image
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
		'input-blob', 'omitted-image', 'binary-mode', 'format', 'v-argv', 'translation-unit', 'scope',
		'old-format', 'link-output', 'link-loads', 'link-environment', 'link-argv', 'link-extracted',
		'link-input', 'link-namespace', 'linked-link-receipt', 'sdk-graph', 'sdk-linked', 'sdk-input', 'old-link-format',
		'denied-policy', 'denied-execution', 'denied-environment', 'denied-exit', 'denied-read', 'denied-installed',
		'denied-output', 'denied-member', 'denied-linked', 'old-sdk-format',
		'closed-policy', 'closed-extra-capability', 'closed-execution', 'closed-environment', 'closed-exit',
		'closed-read', 'closed-allowed', 'closed-hidden', 'closed-output', 'closed-member', 'closed-linked', 'old-denied-format',
		'directory-map', 'directory-policy', 'directory-allowed', 'directory-denied', 'directory-marker', 'old-read-format', 'old-directory-replay-format',
		'metadata-map', 'metadata-policy', 'metadata-aliases', 'metadata-allowed', 'metadata-denied', 'old-metadata-format', 'old-metadata-replay-format'] {
		dir := out + '/' + name
		clone(original, dir)!
		mut proof := json2.decode[Proof](os.read_file(dir + '/host-build.json')!)!
		mut changed := []string{}
		mut expected := ''
		if name == 'old-metadata-format' {
			proof.format = 7
			expected = 'host build declaration differs'
		} else if name in ['metadata-map', 'metadata-policy', 'old-metadata-replay-format'] {
			mut read := json2.decode[HostRead](os.read_file(dir + '/read-closed/receipt.json')!)!
			if name == 'metadata-map' {
				path := read.recorded_directory + '/read-closed/uncaptured-object.o'
				read.metadata << path; read.metadata.sort()
				read.policy += '(allow file-read-metadata (literal "' + path + '"))\n'
			} else if name == 'metadata-policy' { read.policy += '(allow file-read-metadata)\n' }
			else { read.format = 2 }
			for file in ['read-closed/receipt.json', 'read-closed/policy.sb'] {
				os.write_file(dir + '/' + file, if file.ends_with('.json') { json2.encode(read) } else { read.policy })!; changed << file
			}
			expected = 'read-closed capability declaration differs'
		} else if name == 'metadata-aliases' {
			file := 'read-closed/metadata-aliases.json'
			mut aliases := json2.decode[winemetaimages.Aliases](os.read_file(dir + '/' + file)!)!
			aliases.images['/unrecorded/image'] = '/unrecorded/target'
			os.write_file(dir + '/' + file, json2.encode(aliases))!; changed << file
			expected = 'read-closed metadata aliases differ'
		} else if name in ['metadata-allowed', 'metadata-denied'] {
			file := 'read-closed/' + if name == 'metadata-allowed' { 'allowed-metadata-1.log' } else { 'denied-metadata-4.log' }
			os.write_file(dir + '/' + file, 'unrelated failure\n')!; changed << file
			expected = if name == 'metadata-allowed' { 'read-closed metadata allowed control differs' } else { 'read-closed metadata refusal differs' }
		} else if name == 'old-read-format' {
			proof.format = 6
			expected = 'host build declaration differs'
		} else if name in ['directory-map', 'directory-policy', 'old-directory-replay-format'] {
			mut read := json2.decode[HostRead](os.read_file(dir + '/read-closed/receipt.json')!)!
			if name == 'directory-map' {
				path := read.recorded_directory + '/read-closed/unlisted-directory'
				read.directories << path; read.directories.sort()
				read.policy += '(allow file-read-data (require-all (vnode-type DIRECTORY) (literal "' + path + '")))\n'
			} else if name == 'directory-policy' {
				read.policy += '(allow file-read-data (vnode-type DIRECTORY))\n'
			} else { read.format = 1 }
			for file in ['read-closed/receipt.json', 'read-closed/policy.sb'] {
				os.write_file(dir + '/' + file, if file.ends_with('.json') { json2.encode(read) } else { read.policy })!; changed << file
			}
			expected = 'read-closed capability declaration differs'
		} else if name in ['directory-allowed', 'directory-denied', 'directory-marker'] {
			file := 'read-closed/' + match name {
				'directory-allowed' { 'allowed-directory.log' }
				'directory-denied' { 'denied-directory-1.log' }
				else { 'unlisted-directory/marker' }
			}
			os.write_file(dir + '/' + file, 'unrelated failure\n')!; changed << file
			expected = match name {
				'directory-allowed' { 'read-closed directory allowed control differs' }
				'directory-denied' { 'read-closed directory refusal differs' }
				else { 'read-closed directory control differs' }
			}
		} else if name == 'old-denied-format' {
			proof.format = 5
			expected = 'host build declaration differs'
		} else if name == 'closed-linked' {
			file := dir + '/read-closed/receipt.json'
			os.rename(file, file + '-original')!; os.symlink(file + '-original', file)!
			expected = 'read-closed evidence must be bounded and ordinary'
		} else if name == 'closed-policy' || name == 'closed-extra-capability' {
			mut read := json2.decode[HostRead](os.read_file(dir + '/read-closed/receipt.json')!)!
			if name == 'closed-policy' { read.policy = '(allow default)' }
			else {
				read.capabilities[read.recorded_directory + '/read-closed/uncaptured-object.o'] = digest(dir + '/read-closed/uncaptured-object.o')!
				aliases := json2.decode[winemetaimages.Aliases](os.read_file(dir + '/read-closed/metadata-aliases.json')!)!
				extra := winemetaimages.paths(aliases, read.capabilities)
				read.policy = winemetaclosure.policy(read.capabilities.keys(), extra)!
				read.directories = winedirclosure.directories(read.capabilities.keys())!
				read.metadata = winemetaclosure.paths(read.capabilities.keys(), extra)!
			}
			for file in ['read-closed/receipt.json', 'read-closed/policy.sb'] {
				os.write_file(dir + '/' + file, if file.ends_with('.json') { json2.encode(read) } else { read.policy })!; changed << file
			}
			expected = 'read-closed capability declaration differs'
		} else if name == 'closed-execution' {
			file := 'read-closed/captured-closed.exec.json'
			mut exec := json2.decode[map[string]json2.Any](os.read_file(dir + '/' + file)!)!
			exec['policy'] = json2.Any('')
			os.write_file(dir + '/' + file, json2.encode(exec))!; changed << file
			expected = 'read-closed execution record differs'
		} else if name == 'closed-environment' {
			file := 'read-closed/captured-closed.log.environment.json'
			mut env := read_map(dir + '/' + file)!; env['SDKROOT'] = '/unrecorded'
			os.write_file(dir + '/' + file, json2.encode(env))!; changed << file
			expected = 'read-closed child invocation differs'
		} else if name == 'closed-exit' {
			file := 'read-closed/hidden-closed.log.exit.json'
			os.write_file(dir + '/' + file, json2.encode({'exit': 0}))!; changed << file
			expected = 'read-closed child invocation differs'
		} else if name in ['closed-read', 'closed-allowed', 'closed-hidden'] {
			file := 'read-closed/' + match name {
				'closed-read' { 'denied-read-1.log' }
				'closed-allowed' { 'allowed-read.log' }
				else { 'hidden-closed.log' }
			}
			os.write_file(dir + '/' + file, 'unrelated failure\n')!; changed << file
			expected = match name {
				'closed-read' { 'read-closed read refusal differs' }
				'closed-allowed' { 'read-closed allowed control differs' }
				else { 'read-closed hidden refusal differs' }
			}
		} else if name == 'closed-output' || name == 'closed-member' {
			file := 'read-closed/replay/link-inputs/' + if name == 'closed-output' { 'captured-program' } else { 'version.txt' }
			os.write_file(dir + '/' + file, 'changed replay bytes')!; changed << file
			expected = if name == 'closed-output' { 'read-closed replay output differs' } else { 'read-closed captured member differs' }
		} else if name == 'old-sdk-format' {
			proof.format = 4
			expected = 'host build declaration differs'
		} else if name == 'denied-linked' {
			file := dir + '/sdk-denied/receipt.json'
			os.rename(file, file + '-original')!; os.symlink(file + '-original', file)!
			expected = 'SDK-denied evidence must be bounded and ordinary'
		} else if name == 'denied-policy' {
			file := 'sdk-denied/receipt.json'
			mut denied := json2.decode[map[string]json2.Any](os.read_file(dir + '/' + file)!)!
			denied['policy'] = json2.Any('(allow default)')
			os.write_file(dir + '/' + file, json2.encode(denied))!; changed << file
			expected = 'SDK-denied declaration differs'
		} else if name == 'denied-execution' {
			file := 'sdk-denied/captured-denied.exec.json'
			mut denied := json2.decode[map[string]json2.Any](os.read_file(dir + '/' + file)!)!
			denied['sdk_read_denied'] = json2.Any(false)
			os.write_file(dir + '/' + file, json2.encode(denied))!; changed << file
			expected = 'SDK-denied execution record differs'
		} else if name == 'denied-environment' {
			file := 'sdk-denied/captured-denied.log.environment.json'
			mut env := read_map(dir + '/' + file)!; env['SDKROOT'] = '/unrecorded'
			os.write_file(dir + '/' + file, json2.encode(env))!; changed << file
			expected = 'SDK-denied child invocation differs'
		} else if name == 'denied-exit' {
			file := 'sdk-denied/installed-denied.log.exit.json'
			os.write_file(dir + '/' + file, json2.encode({'exit': 0}))!; changed << file
			expected = 'SDK-denied child invocation differs'
		} else if name == 'denied-read' || name == 'denied-installed' {
			file := 'sdk-denied/' + if name == 'denied-read' { 'read-probe-1.log' } else { 'installed-denied.log' }
			os.write_file(dir + '/' + file, 'unrelated failure\n')!; changed << file
			expected = if name == 'denied-read' { 'SDK-denied read refusal differs' } else { 'SDK-denied installed refusal differs' }
		} else if name == 'denied-output' || name == 'denied-member' {
			file := 'sdk-denied/replay/link-inputs/' + if name == 'denied-output' { 'captured-program' } else { 'version.txt' }
			os.write_file(dir + '/' + file, 'changed replay bytes')!; changed << file
			expected = if name == 'denied-output' { 'SDK-denied replay output differs' } else { 'SDK-denied captured member differs' }
		} else if name == 'sdk-graph' {
			file := 'sdk-graph.json'
			os.write_file(dir + '/' + file, '{}\n')!; changed << file
			expected = 'host SDK graph differs'
		} else if name == 'sdk-linked' {
			file := dir + '/sdk-graph.json'
			os.rename(file, file + '-original')!; os.symlink(file + '-original', file)!
			expected = 'host SDK evidence must be bounded and ordinary'
		} else if name == 'sdk-input' {
			path := '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/libSystem.B.tbd'
			if path !in proof.inputs { return error('SDK source omission fixture absent') }
			proof.inputs.delete(path); proof.blobs.delete(path)
			for file in ['inputs.json', 'inputs-after.json'] { os.write_file(dir + '/' + file, json2.encode(proof.inputs))!; changed << file }
			expected = 'host observed input is absent or changed'
		} else if name == 'old-link-format' {
			proof.format = 3
			expected = 'host build declaration differs'
		} else if name == 'old-format' {
			proof.format = 2
			expected = 'host build declaration differs'
		} else if name == 'link-output' {
			file := 'link-replay/link-inputs/program'
			os.write_file(dir + '/' + file, 'changed replay')!; changed << file
			expected = 'host Mach-O replay output differs'
		} else if name == 'link-loads' || name == 'link-namespace' {
			mut link := json2.decode[HostLink](os.read_file(dir + '/host-link.json')!)!
			if name == 'link-loads' { link.loads = map[string]string{} }
			else { link.recorded_directory += '-other' }
			os.write_file(dir + '/host-link.json', json2.encode(link))!; changed << 'host-link.json'
			expected = if name == 'link-loads' { 'host Mach-O load receipt differs' } else { 'host Mach-O link declaration differs' }
		} else if name == 'link-environment' {
			file := 'logs/macho-replay.log.environment.json'
			mut env := read_map(dir + '/' + file)!; env['LIBRARY_PATH'] = '/unrecorded'
			os.write_file(dir + '/' + file, json2.encode(env))!; changed << file
			expected = 'host tool environment differs'
		} else if name == 'link-argv' {
			file := 'logs/macho-replay.log.argv.json'
			os.write_file(dir + '/' + file, json2.encode(['/opt/homebrew/bin/ld64.lld', '@response.txt']))!; changed << file
			expected = 'host Mach-O replay command differs'
		} else if name == 'link-extracted' {
			file := 'link-replay/link-inputs/version.txt'
			os.write_file(dir + '/' + file, 'changed version')!; changed << file
			expected = 'host Mach-O extracted member differs'
		} else if name == 'link-input' {
			path := os.real_path('/opt/homebrew/bin/ld64.lld')
			proof.inputs.delete(path); proof.blobs.delete(path)
			for file in ['inputs.json', 'inputs-after.json'] { os.write_file(dir + '/' + file, json2.encode(proof.inputs))!; changed << file }
			expected = 'host observed input is absent or changed'
		} else if name == 'linked-link-receipt' {
			file := dir + '/host-link.json'
			os.rename(file, file + '-original')!; os.symlink(file + '-original', file)!
			expected = 'Mach-O evidence must be canonical ordinary files'
		} else if name == 'omitted-import' || name == 'omitted-image' {
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
	println('WINE HOST BUILD CONTROLS PASS real baseline copied baseline sixty-two exact refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
