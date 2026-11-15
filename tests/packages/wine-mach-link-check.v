// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import crypto.sha256
import tests.packages.winelink
import tests.packages.winemacholink

struct Proof {
mut:
	format int
	recorded_directory string
	inputs map[string]string
	files map[string]string
}

fn expect(tool string, directory string, expected string) ! {
	mut child := os.new_process(tool)
	defer { child.close() }
	child.set_args(['check', directory]); child.set_redirect_stdio_merged(); child.run()
	text := child.stdout_slurp(); child.wait()
	if expected == '' {
		if child.code != 0 || text != 'WINE MACH-O CAPTURED LINK PASS\n' { return error('Mach-O baseline failed: ' + text) }
	} else if child.code == 0 || text != expected + '\n' { return error('Mach-O refusal differs: ' + text) }
}

fn run() ! {
	if os.args.len != 4 { return error('usage: CHECK MACH_LINK CAPTURE FRESH_CONTROLS') }
	tool := os.real_path(os.args[1]); original := os.real_path(os.args[2]); output := os.abs_path(os.args[3])
	if os.exists(output) || os.is_link(output) { return error('fresh control directory required') }
	os.mkdir_all(output)!
	expect(tool, original, '')!
	baseline := output + '/baseline'
	os.cp_all(original, baseline, false)!
	expect(tool, baseline, '')!
	for name, expected in {
		'format': 'Mach-O proof namespace differs'
		'inventory': 'Mach-O evidence inventory differs'
		'bytes': 'Mach-O evidence bytes differ'
		'output': 'Mach-O replay output differs'
		'argv': 'Mach-O command differs'
		'environment': 'host tool environment differs'
		'images': 'Mach-O version images differ'
		'version': 'Mach-O linker version differs'
		'tool': 'Mach-O selected input changed'
		'tools-absent': 'Mach-O selected tools absent'
		'extracted': 'Mach-O extracted member differs'
		'header': 'Mach-O executable header differs'
		'old-format': 'Mach-O proof namespace differs'
		'trace-empty': 'Mach-O load trace framing differs'
		'trace-absolute': 'Mach-O load trace path differs'
		'trace-escape': 'Mach-O load trace path differs'
		'trace-unparsed': 'Mach-O load trace record differs'
		'trace-missing': 'Mach-O required load observation absent'
		'trace-outside': 'Mach-O loaded file absent from capture'
		'load-receipt': 'Mach-O load receipt differs'
		'capture-omission': 'Mach-O loaded file absent from capture'
	} {
		directory := output + '/' + name
		os.cp_all(original, directory, false)!
		mut proof := json2.decode[Proof](os.read_file(directory + '/macho-link.json')!)!
		mut changed := ''
		match name {
			'format' { proof = Proof{...proof, format: 3} }
			'old-format' { proof = Proof{...proof, format: 1} }
			'inventory' { proof.files.delete('program.c') }
			'bytes' { os.write_file(directory + '/program.c', 'changed\n')! }
			'output' { changed = 'replay/link-inputs/program'; os.write_file(directory + '/' + changed, 'different\n')! }
			'argv' { changed = 'macho-replay.log.argv.json'; os.write_file(directory + '/' + changed, json2.encode(['/opt/homebrew/bin/ld64.lld', '@other.txt']))! }
			'environment' { changed = 'macho-replay.log.environment.json'; os.write_file(directory + '/' + changed, '{}\n')! }
			'images' { changed = 'macho-images-before.json'; os.write_file(directory + '/' + changed, json2.encode({'format': json2.Any(1), 'recorded_directory': json2.Any(proof.recorded_directory), 'images': json2.Any([]json2.Any{})}))! }
			'version' { changed = 'macho-version.log'; os.write_file(directory + '/' + changed, 'different\n')! }
			'tool' { proof.inputs[os.real_path('/opt/homebrew/bin/ld64.lld')] = 'wrong' }
			'tools-absent' { proof.inputs.delete(os.real_path('/opt/homebrew/bin/ld64.lld')) }
			'extracted' {
				changed = 'replay/link-inputs/version.txt'
				os.write_file(directory + '/' + changed, 'different\n')!
			}
			'header' {
				os.write_file(directory + '/program', 'different\n')!
				os.write_file(directory + '/replay/link-inputs/program', 'different\n')!
				proof.files['program'] = sha256.hexhash('different\n')
				proof.files['replay/link-inputs/program'] = sha256.hexhash('different\n')
			}
			'trace-empty' { changed = 'macho-replay.log'; os.write_file(directory + '/' + changed, '')! }
			'trace-absolute', 'trace-escape', 'trace-unparsed', 'trace-outside' {
				changed = 'macho-replay.log'
				extra := match name {
					'trace-absolute' { '/tmp/outside.o\n' }
					'trace-escape' { '../outside.o\n' }
					'trace-outside' { 'outside.o\n' }
					else { 'unparsed output\n' }
				}
				os.write_file(directory + '/' + changed, os.read_file(directory + '/' + changed)! + extra)!
			}
			'trace-missing' {
				changed = 'macho-replay.log'
				text := os.read_file(directory + '/' + changed)!
				os.write_file(directory + '/' + changed, text.split_into_lines()[1..].join('\n') + '\n')!
			}
			'load-receipt' { changed = 'link-loads.json'; os.write_file(directory + '/' + changed, '{}\n')! }
			'capture-omission' {
				archive_path := directory + '/link-inputs.tar'
				bytes := os.read_bytes(archive_path)!
				archive := winelink.parse(bytes)!
				path := 'link-inputs/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk/usr/lib/system/libcache.tbd'
				member := archive.members[path] or { return error('omission fixture absent') }
				mut reduced := bytes[..member.offset - 512].clone()
				reduced << bytes[member.offset + (member.size + 511) / 512 * 512..]
				os.write_file_array(archive_path, reduced)!
				proof.files['link-inputs.tar'] = sha256.hexhash(reduced.bytestr())
				os.rm(directory + '/replay/' + path)!
				proof.files.delete('replay/' + path)
			}
			else { return error('unknown control') }
		}
		if changed != '' { proof.files[changed] = sha256.hexhash(os.read_file(directory + '/' + changed)!) }
		os.write_file(directory + '/macho-link.json', json2.encode(proof) + '\n')!
		expect(tool, directory, expected)!
	}
	bytes := os.read_bytes(original + '/link-inputs.tar')!
	archive := winelink.parse(bytes)!
	proof := json2.decode[Proof](os.read_file(original + '/macho-link.json')!)!
	for before, after in {
		'-dynamic': '-bundle'
		'-o program': '-o /tmp/program'
		'-lm': '-lforeign'
		'-arch arm64': '-arch x86_64'
		'-lto_library ': '-load '
	} {
		changed := winelink.Archive{...archive, response: archive.response.replace(before, after)}
		mut refused := false
		winemacholink.profile(changed, bytes, proof.recorded_directory) or { refused = err.msg() == 'Mach-O response profile differs' }
		if !refused { return error('Mach-O response mutation accepted') }
	}
	lines := archive.response.trim_space().split_into_lines()
	for index in [9, 14] {
		mut changed := bytes.clone()
		member := archive.members['link-inputs/' + lines[index]]
		changed[member.offset] = 0
		mut refused := false
		expected := if index == 9 { 'Mach-O object header differs' } else { 'Mach-O runtime archive header differs' }
		winemacholink.profile(archive, changed, proof.recorded_directory) or { refused = err.msg() == expected }
		if !refused { return error('Mach-O input header mutation accepted') }
	}
	runtime := archive.members['link-inputs/' + lines[14]]
	for position in [4, 16, 24] {
		mut changed := bytes.clone()
		// Excessive fat-slice count, out-of-bounds offset, impossible alignment.
		changed[runtime.offset + position] = 0xff
		mut refused := false
		winemacholink.profile(archive, changed, proof.recorded_directory) or { refused = err.msg() == 'Mach-O runtime archive header differs' }
		if !refused { return error('Mach-O fat archive mutation accepted') }
	}
	println('WINE MACH-O CONTROLS PASS real and copied baselines; twenty-one receipt refusals; five response refusals; five input header refusals')
}

fn main() { run() or { eprintln(err); exit(1) } }
