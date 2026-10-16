// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol
import tools.packages.pkglaunch

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn command_owned_cycles() int { return $if track_heap ? { 1000 } $else { 64 } }

fn command_owned_source(count int) []string {
	mut source := []string{cap: 2 * count + 10}
	unsafe { source.flags |= .noslices }
	source << '--data-cwd'.clone()
	for i in 0 .. count {
		number := i.str(); defer { unsafe { number.free() } }
		source << '--file'.clone(); source << '/home/user/é🚀 space; $literal-' + number
	}
	source << '--'.clone()
	for argument in ['', '-i', 'a\nb', '$(literal)', '@APP@/literal', '--file', '--', '--uid']! { source << argument.clone() }
	return source
}

fn command_owned_refusal(source []string, expected string) {
	if mut value := command_launch(source) { value.close(); assert false }
	else { message := err.msg(); assert message == expected, message; unsafe { message.free(); err.free() } }
}

fn test_command_requests_own_both_vectors_after_source_retirement_and_repeated_close() {
	for count in [0, 1, 64, 256]! {
		mut source := command_owned_source(count)
		mut first := command_launch(source)!
		mut second := command_launch(source)!
		pkgprotocol.free_command_values(mut source)
		assert first.data_cwd && first.documents.len == count
		assert first.arguments == ['', '-i', 'a\nb', '$(literal)', '@APP@/literal', '--file', '--', '--uid']
		if count > 0 { assert first.documents[0] == '/home/user/é🚀 space; $literal-0' }
		first.close(); first.close()
		assert first.arguments.len == 0 && first.documents.len == 0 && !first.data_cwd
		assert second.arguments[4] == '@APP@/literal' && second.documents.len == count
		validate_command(second)!
		second.close(); second.close()
	}
	println('COMMAND OWNERSHIP independent literal arguments/documents survive source and sibling retirement; repeated close resets both vectors and data-cwd PASS')
}

fn test_command_parser_repeat_calls_retire_success_and_refusal_scratch() {
	cycles := command_owned_cycles()
	for count in [0, 1, 64, 256]! {
		mut source := command_owned_source(count)
		defer { pkgprotocol.free_command_values(mut source) }
		mut warm := command_launch(source)!; warm.close()
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			mut value := command_launch(source)!
			assert value.documents.len == count && value.arguments.len == 8 && value.data_cwd
			value.close(); value.close()
		}
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0, count.str() + ': retained ' + kept.str()
			println('COMMAND OWNERSHIP ' + count.str() + ' documents: 1000 parse/close cycles retained 0 bytes')
		}
	}
	mut prefix := []string{cap: 128}
	for _ in 0 .. 64 { prefix << '--file'; prefix << '/home/user/document' }
	defer { unsafe { (&array(&prefix)).free() } }
	cases := [
		[]string{}, ['--bogus', '--'], ['--data-cwd', '--data-cwd', '--'],
		[...prefix], [...prefix, '--bogus', '--'], [...prefix, '--file'],
		[...prefix, '--file', 'relative', '--'], [...prefix, '--file', '/new\nline', '--'],
		[...prefix, '--', 'nul\x00'], [...prefix, '--', 'x'.repeat(4097)],
		[...prefix, '--', ...[]string{len: 16, init: 'x'.repeat(4096)}],
		[...prefix, '--', ...[]string{len: 257, init: ''}],
	]
	messages := [
		'command launch requires the -- argument separator',
		'command launch requires [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]',
		'command launch repeats --data-cwd', 'command launch requires the -- argument separator',
		'command launch requires [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]',
		'command launch requires [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]',
		'command document must be an absolute printable path', 'command document must be an absolute printable path',
		'command argument contains NUL or exceeds 4096 bytes', 'command argument contains NUL or exceeds 4096 bytes',
		'command launch exceeds the 64 KiB input limit', 'command launch exceeds the argument count limit',
	]
	for i, source in cases {
		command_owned_refusal(source, messages[i])
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { command_owned_refusal(source, messages[i]) }
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0, messages[i] + ': retained ' + kept.str()
			println('COMMAND OWNERSHIP refusal ' + i.str() + ': 1000 attempts retained 0 bytes')
		}
	}
	println('COMMAND OWNERSHIP repeated empty/one/64/256-document requests and twelve syntax/string/count/aggregate refusal paths retire all scratch PASS')
}

fn test_command_parser_exact_counts_strings_aggregate_and_prefix_precedence() {
	mut full := command_owned_source(256)
	defer { pkgprotocol.free_command_values(mut full) }
	full << []string{len: 248, init: ''}
	mut maximum := command_launch(full)!; maximum.close()
	full << ''
	command_owned_refusal(full, 'command launch exceeds the argument count limit')
	mut documents := command_owned_source(257)
	defer { pkgprotocol.free_command_values(mut documents) }
	command_owned_refusal(documents, 'command launch exceeds the document count limit')
	for delta in [-1, 0, 1]! {
		mut arguments := []string{cap: 17}; arguments << '--'
		for _ in 0 .. 15 { arguments << 'x'.repeat(4096) }
		arguments << 'x'.repeat(4080 + delta)
		if delta <= 0 { mut value := command_launch(arguments)!; assert value.arguments.len == 16; value.close() }
		else { command_owned_refusal(arguments, 'command launch exceeds the 64 KiB input limit') }
		pkgprotocol.free_command_values(mut arguments)
	}
	// Documents contribute their terminator to the same aggregate byte bound.
	mut combined := []string{cap: 35}
	for _ in 0 .. 15 { combined << '--file'; combined << '/' + 'x'.repeat(4095) }
	combined << '--'; combined << 'x'.repeat(4080)
	mut exact := command_launch(combined)!; exact.close()
	combined << ''
	command_owned_refusal(combined, 'command launch exceeds the 64 KiB input limit')
	// Count refusal precedes path validation, matching the existing parser.
	command_owned_refusal(['--file', 'relative', '--', ...[]string{len: 257, init: ''}], 'command launch exceeds the argument count limit')
	println('COMMAND OWNERSHIP exact 256 arguments/documents, 4096-byte values and 65535/65536/65537 aggregate bytes preserve limits and error precedence PASS')
}

fn test_isolated_transport_validation_retires_borrowed_prefixes_on_both_modes() {
	cycles := command_owned_cycles()
	for mode in ['run-args', 'run-terminal-args']! {
		for count in [0, 1, 64, 256]! {
			mut source := command_owned_source(count)
			defer { pkgprotocol.free_command_values(mut source) }
			vector := [mode, 'app', ...source]
			// Spreading an array borrows its strings; source remains the owner.
			defer { unsafe { (&array(&vector)).free() } }
			pkglaunch.validate_arguments(vector)!
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. cycles { pkglaunch.validate_arguments(vector)! }
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, mode + ' retained ' + kept.str() }
			assert vector[0] == mode && vector[2] == '--data-cwd' && vector.last() == '--uid'
		}
	}
	mut prefix := []string{cap: 130}; prefix << 'run-args'; prefix << 'app'
	for _ in 0 .. 64 { prefix << '--file'; prefix << '/home/user/document' }
	defer { pkgprotocol.free_command_values(mut prefix) }
	cases := [
		[...prefix], [...prefix, '--bogus', '--'], [...prefix, '--file'],
		[...prefix, '--data-cwd', '--data-cwd', '--'], [...prefix, '--file', 'relative', '--'],
		[...prefix, '--', 'nul\x00'], [...prefix, '--', 'x'.repeat(4097)],
		[...prefix, '--', ...[]string{len: 16, init: 'x'.repeat(4096)}],
		[...prefix, '--', ...[]string{len: 257, init: ''}],
	]
	messages := ['isolated command launch requires --', 'invalid isolated command launch options',
		'invalid isolated command launch options', 'invalid isolated command launch options',
		'command document must be an absolute printable path', 'command argument contains NUL or exceeds 4096 bytes',
		'command argument contains NUL or exceeds 4096 bytes', 'command launch exceeds the 64 KiB input limit',
		'command launch exceeds the argument/document count limit']
	for i, source in cases {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles {
			if _ := pkglaunch.validate_arguments(source) { assert false }
			else { message := err.msg(); assert message == messages[i], message; unsafe { message.free(); err.free() } }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, messages[i] + ': retained ' + kept.str() }
	}
	mut source := command_owned_source(256)
	source << []string{len: 248, init: ''}
	pkglaunch.validate_arguments(['run-args', 'app', ...source])!
	mut excess := command_owned_source(257)
	defer { pkgprotocol.free_command_values(mut source); pkgprotocol.free_command_values(mut excess) }
	if _ := pkglaunch.validate_arguments(['run-args', 'app', ...excess]) { assert false }
	else { message := err.msg(); assert message == 'too many isolated launch documents'; unsafe { message.free(); err.free() } }
	$if track_heap ? { println('COMMAND OWNERSHIP transport: both modes, 0/1/64/256 documents and nine refusals repeat 1000 times with 0 retained bytes') }
	println('COMMAND OWNERSHIP isolated transport borrows bounded prefixes, preserves literal source vectors and exact 772-value/document refusal diagnostics PASS')
}
