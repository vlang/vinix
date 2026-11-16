// SPDX-License-Identifier: GPL-2.0-or-later
// Native mutations affect private fixtures only; host qualification is read-only.
module main

import os
import time
import json2
import tests.packages.winesource
import tests.packages.winexattr

#include <sys/xattr.h>
fn C.setxattr(&char, &char, voidptr, uint, u32, int) int
fn C.removexattr(&char, &char, int) int
fn C.mkfifo(&char, u32) int
fn C.listxattr(&char, &char, uint, int) int

const key = 'org.vinix.content-test'
const binary = [u8(0), 255, 128, 65]

struct HostRead {
	format int
	metadata []string
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn seed(path string, name string, value []u8) ! {
	if C.setxattr(path.str, name.str, value.data, uint(value.len), 0, 0) != 0 { return error('fixture setxattr failed') }
}

fn remove(path string, name string) ! {
	if C.removexattr(path.str, name.str, 0) != 0 { return error('fixture removexattr failed') }
}

fn invoke(command []string, log string, positive bool, marker string, seconds int) ! {
	os.write_file(log + '.argv.json', json2.encode(command) + '\n')!
	mut child := os.new_process(command[0])
	defer { child.close() }
	child.set_args(command[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	start := time.now()
	for child.is_alive() {
		if time.since(start).seconds() > seconds {
			child.signal_kill(); child.wait()
			os.write_file(log, child.stdout_slurp())!
			return error('child exceeded bound: ' + log)
		}
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	text := child.stdout_slurp()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': child.code}))!
	require((child.code == 0) == positive && (marker == '' || text.contains(marker)), 'unexpected child outcome: ' + log)!
}

fn check() ! {
	if os.args.len !in [3, 8] { return error('usage: CHECK CONTENT_TOOL FRESH_OUTPUT [HOST_BUILDER FIXTURE CONTROLLER PRODUCER RETAINER]') }
	tool := os.real_path(os.args[1]); out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('fresh xattr control directory required') }
	os.mkdir_all(out)!
	root := os.real_path(out)
	file := root + '/file'; directory := root + '/directory'; empty := root + '/empty'
	os.write_file(file, 'ordinary bytes stay unchanged\n')!; os.mkdir(directory)!; os.write_file(empty, '')!
	seed(file, key, binary)!; seed(file, key + '-empty', [])!; seed(directory, key, binary)!
	targets := root + '/targets.json'; receipt := root + '/receipt.json'
	os.write_file(targets, json2.encode([file, directory, empty]))!
	invoke([tool, 'capture', targets, receipt], root + '/capture.log', true, 'WINE XATTR CONTENT PASS capture', 10)!
	invoke([tool, 'check', targets, receipt], root + '/baseline.log', true, 'WINE XATTR CONTENT PASS check', 10)!
	before := winesource.file_digest(file)!
	sealed := os.read_file(receipt)!
	mut passed := []string{}
	for name in ['same-size-value', 'directory-value', 'added-name', 'removed-name', 'empty-value', 'empty-target', 'renamed-name', 'target-kind'] {
		match name {
			'same-size-value' { seed(file, key, [u8(0), 255, 128, 66])! }
			'directory-value' { seed(directory, key, [u8(2)])! }
			'added-name' { seed(file, key + '-added', binary)! }
			'removed-name' { remove(file, key)! }
			'empty-value' { seed(file, key + '-empty', [u8(1)])! }
			'empty-target' { seed(empty, key, [])! }
			'renamed-name' { remove(file, key)!; seed(file, key + '-renamed', binary)! }
			else { os.rmdir(directory)!; os.write_file(directory, '')!; seed(directory, key, binary)! }
		}
		invoke([tool, 'check', targets, receipt], root + '/' + name + '.log', false, 'native xattr content or declaration differs', 10)!
		match name {
			'added-name' { remove(file, key + '-added')! }
			'empty-target' { remove(empty, key)! }
			'renamed-name' { remove(file, key + '-renamed')! }
			'target-kind' { os.rm(directory)!; os.mkdir(directory)! }
			else {}
		}
		seed(file, key, binary)!; seed(file, key + '-empty', [])!; seed(directory, key, binary)!
		require(winesource.file_digest(file)! == before && os.read_file(receipt)! == sealed, 'native mutation changed ordinary evidence')!
		invoke([tool, 'check', targets, receipt], root + '/' + name + '-restored.log', true, 'WINE XATTR CONTENT PASS check', 10)!
		passed << name
	}
	// Declared binary and empty values must be retained in full, without UTF-8 loss.
	observed := winexattr.capture([file, directory, empty])!
	require(observed[file].values[key.bytes().hex()] == binary.hex() && observed[file].values[(key + '-empty').bytes().hex()] == '', 'binary/empty content differs')!
	for name in ['format', 'scope', 'omitted-object', 'forged-value', 'unknown-field', 'duplicate-field', 'whitespace'] {
		mut decoded := json2.decode[map[string]json2.Any](sealed)!
		match name {
			'format' { decoded['format'] = json2.Any(0) }
			'scope' { decoded['scope'] = json2.Any('forged') }
			'omitted-object' { decoded['objects'] = json2.Any(map[string]json2.Any{}) }
			'forged-value' { require(sealed.contains(binary.hex()), 'binary receipt fixture absent')! }
			else { decoded['unknown'] = json2.Any(true) }
		}
		candidate := root + '/' + name + '.json'
		text := if name == 'forged-value' { sealed.replace_once(binary.hex(), '00ff8042') }
			else if name == 'duplicate-field' { sealed.replace_once('{', '{"format":0,') }
			else if name == 'whitespace' { sealed + '\n' } else { json2.encode(decoded) + '\n' }
		os.write_file(candidate, text)!
		invoke([tool, 'check', targets, candidate], root + '/' + name + '.log', false, 'native xattr content or declaration differs', 10)!
		passed << name
	}
	alias := root + '/alias'; os.symlink(file, alias)!
	fifo := root + '/fifo'; require(C.mkfifo(fifo.str, 0o600) == 0, 'cannot make FIFO')!
	for name, selected in {'empty-targets': []string{}, 'duplicate-target': [file, file], 'relative-target': ['file'],
		'linked-target': [alias], 'missing-target': [root + '/absent'], 'noncanonical-target': [root + '/../' + os.file_name(root) + '/file'],
		'fifo-target': [fifo], 'many-targets': []string{len: winexattr.max_targets + 1, init: file}} {
		manifest := root + '/' + name + '-targets.json'; output := root + '/' + name + '-receipt.json'
		os.write_file(manifest, json2.encode(selected))!
		invoke([tool, 'capture', manifest, output], root + '/' + name + '.log', false, '', 2)!
		require(!os.exists(output), 'invalid target published receipt')!
		passed << name
	}
	os.rm(fifo)!
	for name in ['large-manifest', 'large-receipt', 'fifo-manifest', 'fifo-receipt'] {
		path := root + '/' + name
		if name.starts_with('fifo-') { require(C.mkfifo(path.str, 0o600) == 0, 'cannot make declaration FIFO')! }
		else {
			mut large := os.create(path)!
			if large.write_to(if name == 'large-manifest' { u64(1048576) } else { u64(67108864) }, [u8(0)])! != 1 { return error('cannot create large declaration') }
			large.close()
		}
		output := root + '/' + name + '-receipt.json'
		command := if name.ends_with('manifest') { [tool, 'capture', path, output] } else { [tool, 'check', targets, path] }
		invoke(command, root + '/' + name + '.log', false, 'bounded ordinary xattr declaration required', 2)!
		require(!os.exists(output), 'invalid declaration published receipt')!
		if name.starts_with('fifo-') { os.rm(path)! }
		passed << name
	}
	// Exercise native limits, rather than merely forging an oversized JSON row.
	for name in ['name-bound', 'value-bound', 'total-bound'] {
		mut selected := []string{}
		if name == 'name-bound' {
			path := root + '/many-names'; os.write_file(path, '')!
			for index in 0 .. winexattr.max_names + 1 { seed(path, key + '-' + index.str(), [])! }
			selected << path
		} else {
			for index in 0 .. (if name == 'value-bound' { 1 } else { 17 }) {
				path := root + '/' + name + '-' + index.str(); os.write_file(path, '')!
				seed(path, 'com.apple.ResourceFork', []u8{len: winexattr.max_value + (if name == 'value-bound' { 1 } else { 0 })})!
				selected << path
			}
		}
		manifest := root + '/' + name + '-targets.json'; output := root + '/' + name + '-receipt.json'
		os.write_file(manifest, json2.encode(selected))!
		invoke([tool, 'capture', manifest, output], root + '/' + name + '.log', false,
			if name == 'name-bound' { 'too many xattr names' } else { 'xattr value unreadable or oversized' }, 10)!
		require(!os.exists(output), 'oversized native input published receipt')!
		passed << name
	}
	for name in ['linked-manifest', 'linked-receipt', 'overwrite', 'linked-output'] {
		link := root + '/' + name
		if name != 'overwrite' { os.symlink(if name == 'linked-manifest' { targets } else { receipt }, link)! }
		command := match name {
			'linked-manifest' { [tool, 'check', link, receipt] }
			'linked-receipt' { [tool, 'check', targets, link] }
			'overwrite' { [tool, 'capture', targets, receipt] }
			else { [tool, 'capture', targets, link] }
		}
		invoke(command, root + '/' + name + '.log', false, '', 10)!
		require(os.read_file(receipt)! == sealed, 'publication overwrote receipt')!
		passed << name
	}
	// The default native API hides compression metadata. It must still be pinned.
	compression_source := root + '/compression-source'; compressed := root + '/compressed'
	os.write_file(compression_source, 'compressible native content\n'.repeat(4096))!
	invoke(['/usr/bin/ditto', '--noclone', '--hfsCompression', compression_source, compressed], root + '/compress.log', true, '', 10)!
	require(winesource.file_digest(compression_source)! == winesource.file_digest(compressed)!, 'compressed logical bytes differ')!
	compressed_objects := winexattr.capture([compressed])!
	compression_key := 'com.apple.decmpfs'
	compression_hex := compressed_objects[compressed].values[compression_key.bytes().hex()]
	require(compression_hex.len > 2, 'compressed native fixture absent')!
	mut default_names := [65536]u8{}
	listed := C.listxattr(compressed.str, &char(&default_names[0]), 65536, 0)
	require(listed >= 0 && listed <= 65536, 'default compression survey failed')!
	require(compression_key !in default_names[..listed].bytestr().split('\x00'), 'default API did not hide compression fixture')!
	compression_targets := root + '/compression-targets.json'; compression_receipt := root + '/compression-receipt.json'
	os.write_file(compression_targets, json2.encode([compressed]))!
	invoke([tool, 'capture', compression_targets, compression_receipt], root + '/compression-capture.log', true, 'WINE XATTR CONTENT PASS capture', 10)!
	invoke([tool, 'check', compression_targets, compression_receipt], root + '/compression-check.log', true, 'WINE XATTR CONTENT PASS check', 10)!
	forged := root + '/compression-forged.json'
	compression_text := os.read_file(compression_receipt)!
	require(compression_text.contains(compression_hex), 'compression bytes absent from receipt')!
	os.write_file(forged, compression_text.replace_once(compression_hex, (if compression_hex.starts_with('00') { '01' } else { '00' }) + compression_hex[2..]))!
	invoke([tool, 'check', compression_targets, forged], root + '/hidden-compression-value.log', false, 'native xattr content or declaration differs', 10)!
	passed << 'hidden-compression-value'
	// No native attribute on the historical host graph is changed by qualification.
	if os.args.len == 8 {
		builder := os.real_path(os.args[3])
		for index, role in ['fixture', 'controller', 'producer', 'retainer'] {
			host := os.real_path(os.args[index + 4])
			invoke([builder, 'check', host], root + '/' + role + '-before.log', true, 'WINE HOST BUILD', 30)!
			read := json2.decode[HostRead](os.read_file(host + '/read-closed/receipt.json')!)!
			require(read.format == 4 && read.metadata.len > 0, 'original format-9 query graph required')!
			mut unique := map[string]bool{}
			for path in read.metadata { unique[os.real_path(path)] = true }
			mut selected := unique.keys(); selected.sort()
			manifest := root + '/' + role + '-targets.json'; content := root + '/' + role + '-content.json'
			os.write_file(manifest, json2.encode(selected))!
			invoke([tool, 'capture', manifest, content], root + '/' + role + '-capture.log', true, 'WINE XATTR CONTENT PASS capture', 30)!
			invoke([tool, 'check', manifest, content], root + '/' + role + '-check.log', true, 'WINE XATTR CONTENT PASS check', 30)!
			invoke([builder, 'check', host], root + '/' + role + '-after.log', true, 'WINE HOST BUILD', 30)!
		}
	}
	os.write_file(root + '/result.json', json2.encode(passed) + '\n')!
	println('WINE XATTR CONTENT CONTROLS PASS binary/empty baseline, restored baselines, ' + passed.len.str() + ' exact refusals')
}

fn main() { check() or { eprintln(err); exit(1) } }
