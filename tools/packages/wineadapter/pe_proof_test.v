// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import json2
import os

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
	fn C.vinix_heap_count() u32
	fn C.vinix_heap_size_at(u32) u64
}

// Synthetic receipts exercise admission only. Real PE generation and guest
// execution have separate retained checks; these files are never executed.
fn pe_fixture(work string) ! {
	compiler := work + '/compiler/v'
	mingw := work + '/mingw'
	source := work + '/program.v'
	producer := work + '/producer.v'
	root := work + '/proof'
	for path in [work, work + '/compiler', work + '/compiler/vlib', work + '/compiler/thirdparty', mingw,
		mingw + '/bin', root] { os.mkdir(path)! }
	for path in [compiler, source, producer, work + '/producer', work + '/compiler/vlib/builtin.v',
		work + '/compiler/thirdparty/notice', mingw + '/bin/x86_64-w64-mingw32-gcc',
		mingw + '/bin/x86_64-w64-mingw32-objdump'] { os.write_file(path, path)! }
	os.symlink('builtin.v', work + '/compiler/vlib/link')!
	mut inputs := map[string]PeProofInput{}
	for tree in [work + '/compiler/vlib', work + '/compiler/thirdparty', mingw] {
		pe_inventory(tree, tree, 0, mut inputs)!
	}
	for path in [compiler, source, producer, work + '/producer'] {
		inputs[path] = PeProofInput{kind: 'file', sha256: pe_digest(path)!}
	}
	environment := {
		'PATH': mingw + '/bin:/usr/bin:/bin'
		'HOME': root + '/home', 'TMPDIR': root + '/tmp', 'VMODULES': root + '/modules'
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0'
		'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'
	}
	commands := [
		[compiler, '-backend', 'c', '-prod', '-os', 'windows', '-arch', 'amd64', '-gc', 'none', '-manualfree',
			'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib', '-o', root + '/program.c', root + '/program.v'],
		[mingw + '/bin/x86_64-w64-mingw32-gcc', '-v', '-O2', '-w', '-static', '-municode', '-Wl,--no-insert-timestamp',
			'-Wl,-Map,' + root + '/program.map', '-o', root + '/program.exe', root + '/program.c',
			work + '/compiler/vlib/builtin/core_windows.c', '-lws2_32', '-ladvapi32', '-lshell32'],
		[mingw + '/bin/x86_64-w64-mingw32-objdump', '-p', root + '/program.exe'],
	]
	mut bytes := []u8{len: 256}
	bytes[0] = `M`; bytes[1] = `Z`; bytes[60] = 64; bytes[64] = `P`; bytes[65] = `E`
	bytes[68] = 0x64; bytes[69] = 0x86; bytes[84] = 70; bytes[86] = 2
	bytes[88] = 0x0b; bytes[89] = 2; bytes[156] = 3
	os.write_file_array(root + '/program.exe', bytes)!
	os.cp(source, root + '/program.v')!; os.cp(producer, root + '/producer.v')!
	os.write_file(root + '/program.c', 'synthetic C')!; os.write_file(root + '/program.map', 'synthetic map')!
	os.write_file(root + '/environment.json', json2.encode(environment) + '\n')!
	for name in ['inputs-before-build.json', 'inputs-verified.json']! {
		os.write_file(root + '/' + name, json2.encode(inputs) + '\n')!
	}
	for index, name in ['v.log', 'cc.log', 'pe-headers.log']! {
		os.write_file(root + '/' + name, '')!
		os.write_file(root + '/' + name + '.argv.json', json2.encode(commands[index]) + '\n')!
	}
	mut outputs := map[string]string{}
	for name in ['program.v', 'producer.v', 'program.c', 'program.exe', 'program.map', 'environment.json',
		'inputs-before-build.json', 'inputs-verified.json', 'v.log', 'v.log.argv.json', 'cc.log', 'cc.log.argv.json',
		'pe-headers.log', 'pe-headers.log.argv.json']! { outputs[name] = pe_digest(root + '/' + name)! }
	os.write_file(root + '/proof.json', json2.encode(PeProofRecord{format: 1,
		scope: 'local real Win64 probe producer; input pins are not a hermetic build or a Wine execution result',
		compiler: compiler, mingw_root: mingw, source: source, environment: environment,
		inputs: inputs, outputs: outputs, commands: commands}) + '\n')!
}

fn pe_require(ok bool, message string) { if !ok { panic(message) } }

fn pe_fd() int {
	names := os.ls('/dev/fd') or { panic('cannot measure PE admission descriptors') }
	count := names.len
	unsafe { names.free() }
	return count
}

fn pe_fd_control() {
	before := pe_fd()
	low := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	pe_require(low >= 0, 'cannot open PE descriptor control')
	high := C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC)
	pe_require(high > low, 'PE descriptor control did not create ordered descriptors')
	C.close(low)
	pe_require(pe_fd() == before + 1, 'PE descriptor counter missed a live descriptor above a free gap')
	C.close(high)
	pe_require(pe_fd() == before, 'PE descriptor control did not retire its descriptor')
	println('PE ADMISSION descriptor counter detects a live descriptor above a free gap PASS')
}

fn pe_zero() {
	$if track_heap ? {
		kept := C.vinix_heap_end()
		pe_require(kept == 0, 'PE admission retains V allocations')
	}
}

fn pe_accept(work string) ! {
	root := work + '/proof'
	source := work + '/program.v'
	producer := work + '/producer.v'
	executable := work + '/proof/program.exe'
	defer { unsafe { root.free(); source.free(); producer.free(); executable.free() } }
	mut proof := admit_local_pe_proof(root, source, producer)!
	pe_require(proof.executable == executable, 'selected PE differs')
	pe_require(proof.artifacts.len == 23, 'complete ordinary-file artifact inventory differs')
	proof.close(); proof.close()
}

fn pe_denied(work string, reason string) {
	root := work + '/proof'
	source := work + '/program.v'
	producer := work + '/producer.v'
	defer { unsafe { root.free(); source.free(); producer.free() } }
	mut denied := false
	mut proof := admit_local_pe_proof(root, source, producer) or {
		message := err.msg()
		matches := reason == '' || message.contains(reason)
		if !matches { eprintln(message); eprintln(reason) }
		unsafe { message.free(); err.free() }
		pe_require(matches, 'PE refusal came from an unexpected gate')
		denied = true
		LocalPeProof{}
	}
	proof.close(); proof.close()
	pe_require(denied, 'changed or malformed PE proof admitted')
}

fn pe_deny_reason(work string, reason string) {
	fd := pe_fd()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 16 { pe_denied(work, reason) }
	pe_zero()
	pe_require(pe_fd() == fd, 'PE refusal leaks descriptors')
}

fn pe_deny(work string) { pe_deny_reason(work, '') }

fn pe_write_changed(path string, changed string) ! {
	record := pe_decode(changed)!
	defer { close_pe_record(record) }
	encoded := pe_encode(record)
	text := encoded + '\n'
	defer { unsafe { encoded.free(); text.free() } }
	os.write_file(path, text)!
}

fn pe_reseal(work string, original string, name string, content string) ! {
	file := work + '/proof/' + name
	path := work + '/proof/proof.json'
	defer { unsafe { file.free(); path.free() } }
	mut record := pe_decode(original)!
	defer { close_pe_record(record) }
	os.write_file(file, content)!
	old := record.outputs[name]
	record.outputs[name] = pe_digest(file)!
	unsafe { old.free() }
	text := pe_encode(record)
	line := text + '\n'
	defer { unsafe { text.free(); line.free() } }
	os.write_file(path, line)!
}

fn pe_bad_decode(text string) {
	if decoded := pe_decode(text) {
		close_pe_record(decoded)
		panic('incomplete or malformed receipt JSON decoded')
	} else {
		unsafe { err.free() }
	}
}

fn pe_decoder_failures(original string) {
	// Every truncated prefix exercises ownership after any partially parsed
	// nested map, input row, command array, string or escape. Exclude the final
	// complete object without its newline, which is valid decoder input.
	$if track_heap ? { C.vinix_heap_begin() }
	for length in 0 .. original.len - 1 {
		prefix := unsafe { tos(original.str, length) }
		pe_bad_decode(prefix)
	}
	pe_zero()
	for bad in ['"\\uD800"', '"\\uDC00"', '"\\uD800\\u0041"', '"\\uZZZZ"', '"\\q"', '"\x01"', '"\xff"']! {
		text := '{"format":1,"scope":' + bad + '}'
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 16 { pe_bad_decode(text) }
		pe_zero()
		unsafe { text.free() }
	}
	println('PE ADMISSION every truncated JSON prefix and malformed Unicode retain zero tracked V bytes PASS')
}

fn test_pe_proof_binds_outputs_inputs_commands_and_empty_logs() {
	pe_fd_control()
	work := os.real_path(os.temp_dir()) + '/vinix-pe-admission-' + os.getpid().str()
	defer { os.rmdir_all(work) or {} }
	pe_fixture(work)!
	pe_accept(work)!
	path := work + '/proof/proof.json'
	original := os.read_file(path)!
	defer { unsafe { original.free() } }
	// Canonical schema refusals exercise typed decoding as well as the exact
	// producer schema, including unknown, duplicate and omitted fields.
	for changed in ['{}', original + ' ', original.replace('"format":1', '"format":2'),
		original.replace('"format":1', '"format":1,"format":1'),
		original.replace('"format":1', '"extra":1,"format":1'),
		original.replace('"format":1,', '')] {
		os.write_file(path, changed)!; pe_deny(work)
	}
	os.write_file(path, original)!
	// Resealing hashes cannot change a retained command, environment, copied
	// source, input inventory or executable header independently of the record.
	for name in ['environment.json', 'v.log.argv.json', 'cc.log.argv.json', 'pe-headers.log.argv.json',
		'inputs-before-build.json', 'inputs-verified.json', 'program.v', 'producer.v', 'program.exe']! {
		file := work + '/proof/' + name
		before := os.read_file(file)!
		mut record := pe_decode(original)!
		os.write_file(file, 'resealed invalid content')!
		old := record.outputs[name]
		record.outputs[name] = pe_digest(file)!
		unsafe { old.free() }
		os.write_file(path, json2.encode(record) + '\n')!
		pe_deny(work)
		close_pe_record(record)
		os.write_file(file, before)!; unsafe { before.free() }
		os.write_file(path, original)!
	}
	input := work + '/compiler/vlib/builtin.v'
	before := os.read_file(input)!
	os.write_file(input, 'changed input')!; pe_deny(work); os.write_file(input, before)!
	os.write_file(work + '/compiler/vlib/extra', 'unlisted')!; pe_deny(work); os.rm(work + '/compiler/vlib/extra')!
	os.rm(work + '/compiler/vlib/link')!
	os.symlink('/etc/passwd', work + '/compiler/vlib/link')!; pe_deny(work)
	os.rm(work + '/compiler/vlib/link')!; os.symlink('builtin.v', work + '/compiler/vlib/link')!
	// Output aliases and nonregular inputs refuse without opening a blocking
	// stream; ordinary empty diagnostic files remain valid.
	os.rm(work + '/proof/v.log')!
	os.symlink('../program.v', work + '/proof/v.log')!; pe_deny(work)
	os.rm(work + '/proof/v.log')!; os.write_file(work + '/proof/v.log', '')!
	pe_accept(work)!
	pe_decoder_failures(original)
	// Resealed record-level changes exercise the producer command, canonical
	// path and disjoint-root gates rather than a stale retained-file digest.
	mut command_record := pe_decode(original)!
	old_argument := command_record.commands[0][1]
	command_record.commands[0][1] = '-changed-backend'.clone()
	unsafe { old_argument.free() }
	argv_path := work + '/proof/v.log.argv.json'
	argv_original := os.read_file(argv_path)!
	argv_encoded := pe_encode(command_record.commands[0])
	argv_line := argv_encoded + '\n'
	os.write_file(argv_path, argv_line)!
	old_digest := command_record.outputs['v.log.argv.json']
	command_record.outputs['v.log.argv.json'] = pe_digest(argv_path)!
	unsafe { old_digest.free() }
	command_encoded := pe_encode(command_record)
	command_line := command_encoded + '\n'
	os.write_file(path, command_line)!
	pe_deny_reason(work, 'literal producer commands differ')
	close_pe_record(command_record)
	os.write_file(argv_path, argv_original)!; os.write_file(path, original)!
	unsafe { argv_path.free(); argv_original.free(); argv_encoded.free(); argv_line.free(); command_encoded.free(); command_line.free() }
	compiler := work + '/compiler/v'
	mingw := work + '/mingw'
	root := work + '/proof'
	extra_input := work + '/producer'
	defer { unsafe { compiler.free(); mingw.free(); root.free(); extra_input.free() } }
	for alias in [work + '/compiler/./v', compiler + '\x00suffix', work + '/compiler/../compiler/v'] {
		from := pe_encode(compiler)
		to := pe_encode(alias)
		changed := original.replace(from, to)
		pe_write_changed(path, changed)!
		pe_deny_reason(work, if alias.contains('\x00') { 'invalid Win64 proof input path' } else { 'canonical input paths' })
		unsafe { from.free(); to.free(); changed.free(); alias.free() }
	}
	for alias in [work + '/./producer', extra_input + '\x00suffix', root + '/v.log'] {
		from := pe_encode(extra_input)
		to := pe_encode(alias)
		changed := original.replace(from, to)
		pe_write_changed(path, changed)!
		pe_deny_reason(work, if alias.starts_with(root) { 'overlaps its output directory' } else if alias.contains('\x00') { 'invalid Win64 proof input path' } else { 'canonical' })
		unsafe { from.free(); to.free(); changed.free(); alias.free() }
	}
	for tree in [root, work + '/compiler/vlib'] {
		from := '"mingw_root":' + pe_encode(mingw)
		to := '"mingw_root":' + pe_encode(tree)
		changed := original.replace(from, to)
		pe_write_changed(path, changed)!
		pe_deny_reason(work, if tree == root { 'invalid Win64 proof toolchain tree' } else { 'overlapping Win64 proof toolchain roots' })
		unsafe { from.free(); to.free(); changed.free() }
	}
	os.write_file(path, original)!
	// Each PE refusal is resealed against the changed executable, so a digest
	// check alone cannot satisfy these AMD64 console-identity controls.
	pe_path := work + '/proof/program.exe'
	pe_original := os.read_file(pe_path)!
	for position in [0, 60, 64, 68, 84, 86, 88, 156]! {
		mut bytes := pe_original.bytes()
		bytes[position] = if position == 60 { u8(255) } else { u8(0) }
		changed := bytes.bytestr()
		pe_reseal(work, original, 'program.exe', changed)!
		pe_deny_reason(work, if position == 0 { 'DOS header' } else if position == 60 { 'outside its file' } else { 'AMD64 PE32+ console program' })
		unsafe { bytes.free(); changed.free() }
	}
	os.write_file(pe_path, pe_original)!; os.write_file(path, original)!
	unsafe { pe_path.free(); pe_original.free() }
	println('PE ADMISSION resealed schema/input/output/command/path/overlap/header refusals retain zero tracked V bytes and descriptors PASS')
	fd := pe_fd()
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 { pe_accept(work)! }
	pe_zero()
	pe_require(pe_fd() == fd, 'PE success leaks descriptors')
	println('PE ADMISSION 1000 complete captures and double closes retain zero tracked V bytes and descriptors PASS')
}
