// SPDX-License-Identifier: GPL-2.0-or-later
// Bind the already-qualified executable to retained historical input bytes.
// The C closure is derived from the sealed predecessor; no compiler is run.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os

const state = '/Users/alex/.local/state/vinix/android'
const tool = state + '/maps-framework-boot-tools-2026-11-03-r1'
const predecessor = state + '/maps-webview-package-tools-2026-11-03-r1'
const archive = predecessor + '/current-closure'
const parent_seal = state + '/maps-webview-package-tools-sealed-2026-11-03-r2/sealed'
const audit = state + '/maps-framework-boot-archived-patcher-audit-2026-11-04-r1'
const parent_pin = 'fb121f3d4581e003155af1bcb6d093f1ee5dbc1251825c2551b9a53b2c570ed2'
const executable_pin = '864cd44a611fc4e2f0a5ecb5bc85f2fecaed4ef0768e598a2769b817cc481542'
const source_pin = '42de9aa5b6671b0c6ab08c68666b040be2ce90da9be17896e165abe8a917b623'
const v_compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const project = tool + '/patcher-project-r2'
const old_project = predecessor + '/patcher-project'
const frozen = tool + '/sources-r2'
const source_relative = '/tests/android-webview-browser-probe/patch-kernel.v'
const spawn_relative = '/build-support/android/modulestream/spawn_abi.h'
const stream_relative = '/build-support/android/modulestream/stream.v'

struct Limits {
	rss i64
	wall_ms i64
	reserve i64
	growth i64
	output i64
}
struct Guard {
	argv []string
	generated_root string
	log string
	limits Limits
	exit_code int
	child_exit_code int
	reason string
	cleanup_complete bool
	elapsed_ms i64
	peak_sampled_rss_bytes i64
	initial_free_bytes i64
	minimum_free_bytes i64
	maximum_observed_disk_growth_bytes i64
	output_bytes i64
}
struct Mapping {
	recorded string
	resolved string
	sha256 string
	origin string
	aliases []string
	physical []string
}

fn canonical(path string) bool {
	return path.starts_with('/') && path.len > 1 && !path.ends_with('/')
		&& !path.contains_any('\\\x00\n\r\t \"`')
		&& path[1..].split('/').all(it !in ['', '.', '..'])
}

fn output_allowed(path string) bool {
	if !canonical(path) || !path.starts_with(state + '/') { return false }
	for protected in [tool, predecessor, parent_seal] {
		if path == protected || path.starts_with(protected + '/') || protected.starts_with(path + '/') {
			return false
		}
	}
	return true
}

fn digest(path string) !string {
	if !canonical(path) || os.real_path(path) != path || os.lstat(path)!.get_filetype() != .regular {
		return error('canonical regular physical input required: ' + path)
	}
	size := i64(os.file_size(path))
	// Only the two pinned compiler archives exceed the ordinary source bound.
	bound := if path == archive + '/files' + v_compiler { i64(32) * 1024 * 1024 }
		else if path == archive + '/files/Library/Developer/CommandLineTools/usr/bin/clang' { i64(128) * 1024 * 1024 }
		else { i64(16) * 1024 * 1024 }
	if size < 0 || size > bound { return error('physical input exceeds exact file bound: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := stage.new_host_sha256()!
	defer { hash.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	mut read := i64(0)
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		read += n
		if read > bound || read > size { return error('physical input grew during hashing') }
		hash.update(buffer[..n])!
	}
	if read != size || os.file_size(path) != size || os.real_path(path) != path
		|| os.lstat(path)!.get_filetype() != .regular { return error('physical input changed during hashing') }
	return hash.finish()!
}

fn retain(path string, expected string, mut physical map[string]string) ! {
	actual := digest(path)!
	if !stage.valid_pin(expected) || actual != expected { return error('physical input hash differs: ' + path) }
	if prior := physical[path] { if prior != actual { return error('physical input identity changed') } }
	physical[path] = actual
}

fn snapshot(path string, mut physical map[string]string) ! {
	retain(path, digest(path)!, mut physical)!
}

fn paths(text string, expected int) ![]string {
	if !text.ends_with('\n') || text.contains_any('\r\x00') { return error('canonical newline-terminated input list required') }
	items := text[..text.len - 1].split('\n')
	if items.len != expected || items != items.sorted() { return error('complete sorted input list required') }
	mut seen := map[string]bool{}
	for item in items {
		if !canonical(item) || item in seen { return error('unique canonical input required') }
		seen[item] = true
	}
	return items
}

fn validate_index(pins map[string]string, resolved map[string]string) ! {
	if pins.len == 0 || pins.keys().sorted() != resolved.keys().sorted() { return error('complete matching archive maps required') }
	for key, pin in pins {
		if !canonical(key) || !canonical(resolved[key]) || !stage.valid_pin(pin) { return error('noncanonical archive identity') }
	}
}

fn mapping(recorded string, pins map[string]string, resolved map[string]string) !Mapping {
	if !canonical(recorded) { return error('noncanonical recorded input') }
	target := if recorded in pins { resolved[recorded] } else { recorded }
	mut aliases := []string{}
	mut pin := ''
	for key in pins.keys().sorted() {
		if target != recorded && resolved[key] == recorded {
			return error('recorded path is an ambiguous alias and resolved target')
		}
		if resolved[key] == target {
			if pin != '' && pin != pins[key] { return error('ambiguous archived aliases') }
			pin = pins[key]
			aliases << key
		}
	}
	if aliases.len == 0 { return error('recorded input absent from archived maps: ' + recorded) }
	return Mapping{recorded: recorded, resolved: target, sha256: pin, origin: 'sealed-predecessor', aliases: aliases,
		physical: aliases.map(archive + '/files' + it)}
}

fn select_input(recorded string, pins map[string]string, resolved map[string]string,
	mut selected map[string]Mapping, mut physical map[string]string) ! {
	row := mapping(recorded, pins, resolved)!
	for path in row.physical { retain(path, row.sha256, mut physical)! }
	selected[recorded] = row
}

fn text(path string, mut physical map[string]string) !string {
	snapshot(path, mut physical)!
	return os.read_file(path)!
}

// C phase-two splicing applies before recognizing a directive. Keep the full
// logical record, including every continued replacement/condition line.
fn cpp_records(source string) ![]string {
	if !source.ends_with('\n') || source.contains_any('\r\x00') { return error('complete LF C source required') }
	mut records := []string{}
	mut logical := ''
	mut continuing := false
	for line in source[..source.len - 1].split('\n') {
		continuing = line.ends_with('\\')
		logical += if continuing { line[..line.len - 1] } else { line }
		if continuing { continue }
		if logical.trim_left(' \t').starts_with('%:') { return error('alternate directive syntax is not generated here') }
		if logical.trim_left(' \t').starts_with('#') { records << logical }
		logical = ''
	}
	if continuing { return error('truncated continued directive') }
	return records
}

fn compare_c(before string, after string, before_spawn string, after_spawn string) !int {
	old_include := '#include "' + before_spawn + '"'
	new_include := '#include "' + after_spawn + '"'
	if before.count(old_include) != 1 || after.count(new_include) != 1
		|| before_spawn == after_spawn { return error('exact unique frozen spawn include required') }
	normalized := after.replace(new_include, old_include)
	left, right := cpp_records(before)!, cpp_records(normalized)!
	if left != right { return error('logical C preprocessor records differ') }
	// Retain the complete compiler/platform prolog, including non-directive C.
	marker := 'typedef struct main__'
	a := before.index(marker) or { return error('original generated C prolog absent') }
	b := normalized.index(marker) or { return error('qualified generated C prolog absent') }
	if before[..a] != normalized[..b] { return error('generated compiler/platform prolog differs') }
	return left.len
}

fn command_tokens(value string) ![]string {
	if !value.ends_with('\n') || value.count('\n') != 1 || value.contains_any("'\"`\r\t\\\x00") {
		return error('literal emitted C command required')
	}
	items := value.trim_space().split(' ')
	if items.len < 10 || items[0] != 'cc' || items.any(it == '' || it.contains_any('$;&|<>()')) {
		return error('strict emitted C argv required')
	}
	return items
}

fn compare_argv(before []string, after []string, old_c string, new_c string, old_out string, new_out string) ! {
	if before.len != after.len || old_c == new_c || old_out == new_out
		|| before.filter(it == old_c).len != 1 || before.filter(it == old_out).len != 1
		|| after.filter(it == new_c).len != 1 || after.filter(it == new_out).len != 1 {
		return error('exact owned C/output argv required')
	}
	mut normalized := after.clone()
	for i, item in normalized {
		if item == new_c { normalized[i] = old_c }
		if item == new_out { normalized[i] = old_out }
	}
	if before != normalized { return error('C compiler argv differs outside exact owned paths') }
}

fn guard(path string, argv []string, generated string, log string, growth i64,
	wall i64, mut physical map[string]string) ! {
	row := json2.decode[Guard](text(path, mut physical)!)!
	if row.argv != argv || row.generated_root != generated || row.log != log
		|| row.exit_code != 0 || row.child_exit_code != 0 || row.reason != '' || !row.cleanup_complete
		|| row.limits.rss != 600 * 1024 * 1024 || row.limits.wall_ms != wall
		|| row.limits.growth != growth || row.limits.reserve != 1024 * 1024 * 1024
		|| row.limits.output != 4 * 1024 * 1024 || row.elapsed_ms > wall || row.elapsed_ms <= 0
		|| row.peak_sampled_rss_bytes > row.limits.rss || row.minimum_free_bytes < row.limits.reserve
		|| row.maximum_observed_disk_growth_bytes > growth || row.output_bytes > row.limits.output {
		return error('qualified original successful guard/argv/caps required: ' + path)
	}
	snapshot(log, mut physical)!
}

fn verify(work string) ! {
	mut physical := map[string]string{}
	retain(parent_seal + '/manifest.json', parent_pin, mut physical)!
	guard(audit + '/parent-readback.guard.json', ['/usr/bin/time', '-l', parent_seal + '/seal', 'check', '--out', parent_seal,
		'--pin', parent_pin], parent_seal, audit + '/parent-readback.log', 64 * 1024 * 1024, 900000, mut physical)!
	parent_log := os.read_file(audit + '/parent-readback.log')!
	if parent_log.count('STREAM-EVIDENCE CHECK PASS roots=3 entries=19661 manifest=' + parent_pin) != 1 {
		return error('complete original parent seal readback missing')
	}
	retain(archive + '/inputs.json', '76b77e99c325d772f979dbfa41566f966cb218cbb09bff4accbbde2811130112', mut physical)!
	retain(archive + '/resolved.json', '28ac72d87a6b94e8a0eb887f49006b5d12b344cc6724aa82f6f9ece80b094e99', mut physical)!
	pins := json2.decode[map[string]string](os.read_file(archive + '/inputs.json')!)!
	resolved := json2.decode[map[string]string](os.read_file(archive + '/resolved.json')!)!
	validate_index(pins, resolved)!
	if pins.len != 862 { return error('exact complete predecessor archive map required') }
	mut selected := map[string]Mapping{}
	retain(tool + '/patcher-inputs-r2.txt', '2791a3daa0d00eae3246d41aa8930bb8e0a2ec137ad9060262330129f32fd298', mut physical)!
	v_inputs := paths(os.read_file(tool + '/patcher-inputs-r2.txt')!, 355)!
	frozen_pins := {
		frozen + source_relative: source_pin
		frozen + spawn_relative: '9b0185468cd58b36dfdf4a17d776ef44fd30006947f2d54b80bf07b18d886b24'
		frozen + stream_relative: '00e2bd182954bd13672c0550ef9d73ade9904f44f81b13afb4872428487d3fef'
	}
	mut frozen_count := 0
	for path in v_inputs {
		if path in frozen_pins {
			retain(path, frozen_pins[path], mut physical)!
			selected[path] = Mapping{recorded: path, resolved: path, sha256: frozen_pins[path],
				origin: 'exact-frozen-source', physical: [path]}
			frozen_count++
		}
		else { select_input(path, pins, resolved, mut selected, mut physical)! }
	}
	if frozen_count != 3 { return error('exact three frozen source inputs required') }
	for path in [v_compiler, '/Library/Developer/CommandLineTools/usr/bin/clang'] {
		select_input(path, pins, resolved, mut selected, mut physical)!
		if selected[path].aliases != [path] || selected[path].resolved != path {
			return error('exact archived compiler alias required for its bounded file')
		}
	}
	for name in ['c-inputs.txt', 'c-inputs.json', 'c-inputs.raw', 'missing-include-directories.json'] {
		path := predecessor + '/patcher-discovery/' + name
		// These discovery records are bound by the original full parent seal.
		snapshot(path, mut physical)!
	}
	retain(predecessor + '/patcher-discovery/c-inputs.txt', '29f32d64b12e36232589c53e8a7457ff66cbc11debfdbc8971f5b6ae238a1032', mut physical)!
	c_inputs := paths(os.read_file(predecessor + '/patcher-discovery/c-inputs.txt')!, 405)!
	for path in c_inputs { select_input(path, pins, resolved, mut selected, mut physical)! }
	// The predecessor closure includes all support C files and their headers.
	// Only the frozen spawn header path changes in the compiler input logic.
	before_c := text(old_project + '/patch-kernel.c', mut physical)!
	retain(old_project + '/patch-kernel.c', pins[old_project + '/patch-kernel.c'], mut physical)!
	retain(project + '/patch-kernel.c', '31a9bc9f190026a9d5767d3d5973307af59ea3d88ea822381429e71829519874', mut physical)!
	after_c := os.read_file(project + '/patch-kernel.c')!
	retain(predecessor + '/sources' + spawn_relative, frozen_pins[frozen + spawn_relative], mut physical)!
	directives := compare_c(before_c, after_c, predecessor + '/sources' + spawn_relative, frozen + spawn_relative)!
	before_argv := command_tokens(text(old_project + '/build_command.txt', mut physical)!)!
	after_argv := command_tokens(text(project + '/build_command.txt', mut physical)!)!
	compare_argv(before_argv, after_argv, old_project + '/patch-kernel.c', project + '/patch-kernel.c',
		old_project + '/patch-kernel', project + '/patch-kernel')!
	// Bind the original sealed discovery argv to the same full predecessor command.
	discovery := json2.decode[map[string]json2.Any](os.read_file(predecessor + '/patcher-discovery/c-inputs.json')!)!
	mut dependency_argv := ['/usr/bin/cc', '-M']
	mut skip := false
	for token in before_argv[1..] {
		if skip { skip = false; continue }
		if token == '-o' { skip = true; continue }
		dependency_argv << token
	}
	discovery_exit := discovery['exit_code'] or { return error('original C discovery exit code missing') }
	discovery_argv := discovery['argv'] or { return error('original C discovery argv missing') }
	if discovery_exit.int() != 0 || discovery_argv.as_array().map(it.str()) != dependency_argv {
		return error('original sealed C discovery argv differs')
	}
	retain(project + '/patch-kernel', executable_pin, mut physical)!
	retain(tool + '/patcher-generate-r2.guard.json', '24a90da0575ec1a2c0458b6d0f8c89a3d92e6cfcd1ab7032dbff4c6f1d7e6408', mut physical)!
	generate := ['/usr/bin/time', '-l', '/usr/bin/env', 'VROOT=' + os.dir(v_compiler), 'V=' + v_compiler,
		'VINIX_V_COMPILER=' + v_compiler, v_compiler, '-new-compiler', '-prod', '-gc', 'boehm', '-nocache',
		'-cc', 'cc', '-showcc', '-no-parallel', '-dump-files', tool + '/patcher-inputs-r2.txt',
		'-generate-c-project', project, '-path', frozen + '/tests/native-android-ws|' + frozen + '/build-support|' + frozen + '/build-support/android|@vlib', frozen + source_relative]
	guard(tool + '/patcher-generate-r2.guard.json', generate, project, tool + '/patcher-generate-r2.log',
		512 * 1024 * 1024, 300000, mut physical)!
	retain(tool + '/patcher-c-compile-r2.guard.json', '430f4cc3b4966c77a85c0fef8703c3d8462ec99ba38017e85733a0ea22035219', mut physical)!
	guard(tool + '/patcher-c-compile-r2.guard.json', ['/usr/bin/time', '-l', 'make', '-s', '-C', project],
		project, tool + '/patcher-c-compile-r2.log', 512 * 1024 * 1024, 300000, mut physical)!
	retain(tool + '/patcher-selftest-r3.guard.json', 'f76ee661ee847c03dfe32fdc0e5733b3501cefcb950f64c318dab482602a341c', mut physical)!
	guard(tool + '/patcher-selftest-r3.guard.json', ['/usr/bin/time', '-l', project + '/patch-kernel', '--self-test'],
		project, tool + '/patcher-selftest-r3.log', 512 * 1024 * 1024, 300000, mut physical)!
	retain(tool + '/patcher-selftest-r3.log', '14010704a3c01903d355dd0d25fca7a4b74aa1829354d27b4d7d7475d3631a9d', mut physical)!
	log := os.read_file(tool + '/patcher-selftest-r3.log')!
	if log.count(' KERNEL-PROFILE-SELF-TEST PASS ') != 52 || log.count(' FAT-SELF-TEST PASS ') != 45
		|| log.count('BROWSER-KERNEL-PATCH SELF-TEST PASS configuration inventory digest symlink launched-stage guards') != 1
		|| log.count('MAPS-FRAMEWORK-BOOT KERNEL-PROFILE-SELF-TEST PASS ') != 1
		|| log.count('/framework-boot/stage/kernel-patch.json') != 1 { return error('complete original qualified full suite missing') }
	for name, pin in {
		'Makefile': '37dab80e430fe10604e6ac8520e26acadfe9808b0563568cf92d337d1247af64'
		'build.sh': 'a07681d5ce1f7b70a0eed7630474f92add7c4e93a35df80a3b5083251dc3e09a'
		'build.bat': '903325d518bf31a36898cd816380046442c58208d2079ec61923e5edd9bede57'
		'build_command.txt': '3e2207858561f422c1a7de9f80b7807a1099f5c18459d5802ca0e4db9a31aee8'
	} { retain(project + '/' + name, pin, mut physical)! }
	// These failed/earlier records are retained as evidence, never treated as a pass.
	for name in ['patcher-inputs.txt', 'patcher-generate.guard.json', 'patcher-generate.log',
		'patcher-selftest-r2.guard.json', 'patcher-selftest-r2.log', 'qualification-pending.md',
		'qualification-completed-r3.md', 'source-copy.guard.json', 'source-copy.log',
		'source-copy-r2.guard.json', 'source-copy-r2.log', 'source-refresh-patcher-r2.guard.json',
		'source-refresh-patcher-r2.log'] { snapshot(tool + '/' + name, mut physical)! }
	for relative in [source_relative, stream_relative, spawn_relative] { snapshot(tool + '/sources' + relative, mut physical)! }
	snapshot(os.real_path(@FILE), mut physical)!
	snapshot(os.real_path(os.executable()), mut physical)!
	// Read back every selected physical byte before publishing the mapping.
	for path, pin in physical { if digest(path)! != pin { return error('selected input changed before receipt') } }
	os.write_file(work + '/mapping.json', json2.encode(selected, prettify: true) + '\n')!
	os.write_file(work + '/physical-inputs.txt', physical.keys().sorted().join('\n') + '\n')!
	os.write_file(work + '/physical-pins.json', json2.encode(physical, prettify: true) + '\n')!
	os.write_file(work + '/receipt.json', json2.encode({
		'format': json2.Any('vinix-framework-boot-archived-patcher-v1'),
		'parent_seal': json2.Any(parent_seal), 'parent_pin': json2.Any(parent_pin),
		'executable': json2.Any(project + '/patch-kernel'), 'executable_sha256': json2.Any(executable_pin),
		'source_sha256': json2.Any(source_pin), 'original_v_records': json2.Any(355),
		'frozen_source_records': json2.Any(3), 'predecessor_c_records': json2.Any(405),
		'logical_cpp_records': json2.Any(directives), 'physical_inputs': json2.Any(physical.len),
		'proof_limit': json2.Any('Historical C closure derived from sealed predecessor and identical logical CPP/prolog/compiler argv; no contemporaneous rediscovery claimed.'),
		'failed_scratch': json2.Any(tool + '/patcher-selftest-r2-scratch; retained separately as a complete evidence root'),
		'new_sdk27_2_patcher': json2.Any('unqualified; no qualification transfer'),
	}, prettify: true) + '\n')!
	println('FRAMEWORK-BOOT-ARCHIVED-PATCHER PASS V=355 frozen=3 predecessor-C=405 physical=' + physical.len.str())
}

fn self_test(work string) ! {
	mut controls := 0
	base := '/historical/input.h'
	target := '/historical/sdk/input.h'
	pin := sha256.sum('bytes'.bytes()).hex()
	good := {base: pin}
	resolved := {base: target}
	validate_index(good, resolved)!
	assert mapping(target, good, resolved)!.aliases == [base]
	assert mapping(base, {base: pin, '/same-bytes': pin}, {base: target, '/same-bytes': target})!.aliases.len == 2
	for value in ['/historical/../input.h', '//historical/input.h', '/historical/input.h/', '/historical/./input.h'] {
		assert !canonical(value); controls++
	}
	assert output_allowed(audit + '/synthetic-fresh-output')
	for value in [tool, tool + '/fresh-output', predecessor + '/current-closure/fresh-output',
		parent_seal + '/fresh-output', os.dir(parent_seal), state, '/private/tmp/fresh-output'] {
		assert !output_allowed(value); controls++
	}
	for value in ['z\n', base + '\n' + base + '\n', target + '\n' + base + '\n', base] {
		mut refused := false
		paths(value, 2) or { refused = true }
		assert refused; controls++
	}
	for pins in [map[string]string{}, {base: 'bad'}, {base: pin}, {base: pin, '/alias': 'a'.repeat(64)}] {
		// Each independent malformed index/alias case below uses the real selector.
		mut refused := false
		if pins.len == 0 { validate_index(pins, resolved) or { refused = true } }
		else if pins.len == 1 && pins[base] == 'bad' { validate_index(pins, resolved) or { refused = true } }
		else if pins.len == 1 { mapping('/missing/input.h', pins, resolved) or { refused = true } }
		else { mapping(target, pins, {base: target, '/alias': target}) or { refused = true } }
		assert refused; controls++
	}
	for locations in [{base: '/noncanonical/../input.h'}, {target: base}, {base: target, '/alias': base}] {
		mut refused := false
		if locations.len == 1 { validate_index(good, locations) or { refused = true } }
		else { mapping(base, {base: pin, '/alias': pin}, locations) or { refused = true } }
		assert refused; controls++
	}
	before := '#define CHOICE(x) ' + '\\' + '\n' + '  ((x) + 1)\n#include "/old/spawn.h"\ntypedef struct main__T main__T;\n'
	after := before.replace('/old/spawn.h', '/new/spawn.h')
	assert compare_c(before, after, '/old/spawn.h', '/new/spawn.h')! == 2
	for mutant in [after.replace('((x) + 1)', '((x) + 2)'), after.replace('#define', '#undef'),
		after.replace('typedef struct main__T', 'int extra;\ntypedef struct main__T'),
		after.replace('/new/spawn.h', '/new/other.h'), after + '#define TRAILING ' + '\\' + '\n'] {
		mut refused := false
		compare_c(before, mutant, '/old/spawn.h', '/new/spawn.h') or { refused = true }
		assert refused; controls++
	}
	mut truncated_refused := false
	cpp_records('#define TRAILING ' + '\\' + '\n') or {
		assert err.msg() == 'truncated continued directive'
		truncated_refused = true
	}
	assert truncated_refused; controls++
	left := ['cc', '-o', '/old/run', '-x', 'objective-c', '/old/input.c', '-O2']
	right := ['cc', '-o', '/new/run', '-x', 'objective-c', '/new/input.c', '-O2']
	compare_argv(left, right, '/old/input.c', '/new/input.c', '/old/run', '/new/run')!
	mut extra := right.clone()
	extra << '-DCHANGED'
	for mutant in [right[..6].clone(), extra, right.map(if it == '-O2' { '-O0' } else { it }),
		['cc', '-x', 'objective-c', '-o', '/new/run', '/new/input.c', '-O2']] {
		mut refused := false
		compare_argv(left, mutant, '/old/input.c', '/new/input.c', '/old/run', '/new/run') or { refused = true }
		assert refused; controls++
	}
	// Missing and modified archive bytes are tested in our fresh synthetic root.
	path := work + '/synthetic-input.h'
	os.write_file(path, 'bytes')!
	mut physical := map[string]string{}
	retain(path, pin, mut physical)!
	for candidate in [work + '/missing-input.h', path] {
		mut refused := false
		retain(candidate, '0'.repeat(64), mut physical) or { refused = true }
		assert refused; controls++
	}
	os.write_file(path, 'other')!
	mut refused := false
	retain(path, pin, mut physical) or { refused = true }
	assert refused; controls++
	os.write_file(work + '/controls.json', json2.encode({'negative_controls': json2.Any(controls),
		'live_evidence_mutations': json2.Any(0)}, prettify: true) + '\n')!
	println('FRAMEWORK-BOOT-ARCHIVED-PATCHER SELF-TEST PASS controls=' + controls.str())
}

fn main() {
	if os.args.len != 3 || os.args[1] !in ['--verify', '--self-test'] { eprintln('usage: framework-boot-archived-patcher --verify|--self-test FRESH_EXTERNAL_OUTPUT'); exit(2) }
	work := os.args[2]
	if !output_allowed(work) || os.exists(work) || os.is_link(work)
		|| os.real_path(os.dir(work)) != os.dir(work) { eprintln('fresh canonical external output required'); exit(2) }
	os.mkdir(work, mode: 0o700) or { eprintln(err); exit(1) }
	if os.args[1] == '--self-test' { self_test(work) or { eprintln(err); exit(1) } }
	else { verify(work) or { eprintln(err); exit(1) } }
}
