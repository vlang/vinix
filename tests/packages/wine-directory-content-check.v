// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import json2
import tests.packages.winedircontent

fn C.mkfifo(&char, u32) int

struct Replay { directories []string }
struct Format { format int }

fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn invoke(command []string, log string, positive bool, marker string, seconds int) ! {
	os.write_file(log + '.argv.json', json2.encode(command))!
	mut child := os.new_process(command[0])
	defer { child.close() }
	child.set_args(command[1..]); child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	start := time.now()
	for child.is_alive() {
		if time.since(start).seconds() >= seconds {
			child.signal_kill(); child.wait(); os.write_file(log, child.stdout_slurp())!
			return error('directory content command timed out: ' + log)
		}
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	text := child.stdout_slurp()
	os.write_file(log, text)!
	os.write_file(log + '.exit.json', json2.encode({'exit': child.code}))!
	require(child.code == (if positive { 0 } else { 1 }) && (marker == '' || text.contains(marker)), 'directory content command reached wrong gate: ' + log)!
}

fn guards() ! {
	if os.args.len != 5 { return error('usage: CHECK guards COMPILER FRESH_OUTPUT') }
	compiler := os.real_path(os.args[2]); output := os.abs_path(os.args[3])
	// Require an explicit final marker, preventing accidental positional runs.
	if os.args[4] != '--source-guards' { return error('source guard mode required') }
	if os.exists(output) || os.is_link(output) { return error('fresh source guard output required') }
	os.mkdir_all(output + '/code/tests/packages/winedircontent')!
	root := os.real_path(output); code := root + '/code'
	for path in ['wine-directory-content.v', 'winedircontent/content.v'] {
		os.write_file(code + '/tests/packages/' + path, os.read_file(os.dir(@FILE) + '/' + path)!)!
	}
	os.mkdir(root + '/empty')!
	manifest := root + '/targets.json'; os.write_file(manifest, json2.encode([root + '/empty']))!
	mut passed := []string{}
	for mode in ['production', 'nonproduction'] {
		mut command := [compiler, '-backend', 'c', '-gc', 'boehm', '-path', '@vlib|' + code + '|@vmodules', '-o', root + '/' + mode, code + '/tests/packages/wine-directory-content.v']
		if mode == 'production' { command.insert(1, '-prod') }
		invoke(command, root + '/' + mode + '-compile.log', true, '', 60)!
	}
	invoke([root + '/production', 'capture', manifest, root + '/baseline.json'], root + '/baseline.log', true, 'WINE DIRECTORY CONTENT PASS capture', 2)!
	invoke([root + '/nonproduction', 'capture', manifest, root + '/nonproduction.json'], root + '/nonproduction.log', false, 'production directory inventory required', 2)!
	require(!os.exists(root + '/nonproduction.json'), 'nonproduction guard published a receipt')!
	passed << 'nonproduction'
	for path in ['wine-directory-content.v', 'winedircontent/content.v'] {
		file := code + '/tests/packages/' + path; original := os.read_file(file)!
		os.write_file(file, original + '\n')!
		name := if path.contains('/') { 'reader-source' } else { 'main-source' }
		invoke([root + '/production', 'capture', manifest, root + '/' + name + '.json'], root + '/' + name + '.log', false, 'compiled directory inventory source differs', 2)!
		require(!os.exists(root + '/' + name + '.json'), 'source guard published a receipt')!
		os.write_file(file, original)!
		invoke([root + '/production', 'check', manifest, root + '/baseline.json'], root + '/' + name + '-restored.log', true, 'WINE DIRECTORY CONTENT PASS check', 2)!
		passed << name
	}
	os.write_file(root + '/result.json', json2.encode(passed))!
	println('WINE DIRECTORY SOURCE GUARDS PASS three exact refusals and restored baselines')
}

fn check() ! {
	if os.args.len !in [3, 8] { return error('usage: CHECK CONTENT FRESH_OUTPUT [ORIGINAL_BUILDER FIXTURE CONTROLLER PRODUCER RETAINER]') }
	tool := os.real_path(os.args[1]); output := os.abs_path(os.args[2])
	if os.exists(output) || os.is_link(output) { return error('fresh directory control output required') }
	os.mkdir_all(output)!
	root := os.real_path(output); empty := root + '/empty'; filled := root + '/filled'
	os.mkdir(empty)!; os.mkdir(filled)!; os.mkdir(filled + '/subdirectory')!
	file := filled + '/ordinary'; fifo := filled + '/fifo'
	os.write_file(file, 'ordinary bytes\n')!; os.write_file(filled + '/.hidden', '')!
	os.write_file(filled + '/quote"-backslash\\-newline\n', '')!
	os.write_file(filled + '/unicode-λ', '')!
	os.symlink('absent', filled + '/dangling')!; os.symlink('cycle', filled + '/cycle')!
	require(C.mkfifo(fifo.str, 0o600) == 0, 'cannot make entry FIFO')!
	manifest := root + '/targets.json'; receipt := root + '/receipt.json'
	selected := [empty, filled]
	os.write_file(manifest, json2.encode(selected))!
	invoke([tool, 'capture', manifest, receipt], root + '/capture.log', true, 'WINE DIRECTORY CONTENT PASS capture', 2)!
	invoke([tool, 'check', manifest, receipt], root + '/baseline.log', true, 'WINE DIRECTORY CONTENT PASS check', 2)!
	observed := winedircontent.capture(selected)!
	require(observed[empty].len == 0, 'empty directory or dot entries encoded incorrectly')!
	mut native := os.ls(filled)!.map(it.bytes().hex()); native.sort()
	require(native == observed[filled] && native.len == 8, 'native entry names lost or followed')!
	sealed := os.read_file(receipt)!
	mut passed := []string{}
	for name in ['added-entry', 'removed-entry', 'renamed-entry', 'hidden-entry', 'target-kind', 'target-link'] {
		backup := root + '/saved'
		match name {
			'added-entry' { os.write_file(filled + '/added', '')! }
			'hidden-entry' { os.write_file(filled + '/.added', '')! }
			'removed-entry' { os.rename(file, backup)! }
			'renamed-entry' { os.rename(file, filled + '/renamed')! }
			'target-kind' { os.rename(empty, backup)!; os.write_file(empty, '')! }
			'target-link' { os.rename(empty, backup)!; os.symlink(backup, empty)! }
			else {}
		}
		invoke([tool, 'check', manifest, receipt], root + '/' + name + '.log', false,
			if name == 'target-kind' { 'directory target required' } else if name == 'target-link' { 'canonical unique directory targets required' } else { 'native directory content or declaration differs' }, 2)!
		match name {
			'added-entry' { os.rm(filled + '/added')! }
			'hidden-entry' { os.rm(filled + '/.added')! }
			'removed-entry' { os.rename(backup, file)! }
			'renamed-entry' { os.rename(filled + '/renamed', file)! }
			else { os.rm(empty)!; os.rename(backup, empty)! }
		}
		require(os.read_file(receipt)! == sealed && os.read_file(file)! == 'ordinary bytes\n', 'name control changed receipt or ordinary file bytes')!
		invoke([tool, 'check', manifest, receipt], root + '/' + name + '-restored.log', true, 'WINE DIRECTORY CONTENT PASS check', 2)!
		passed << name
	}
	// Immediate names deliberately do not bind child bytes, kinds, link bodies or descendants.
	os.write_file(file, 'changed bytes\n')!
	os.rm(filled + '/dangling')!; os.symlink('different-absent', filled + '/dangling')!
	os.write_file(filled + '/subdirectory/nested', '')!
	os.rm(filled + '/.hidden')!; os.mkdir(filled + '/.hidden')!
	invoke([tool, 'check', manifest, receipt], root + '/child-independent.log', true, 'WINE DIRECTORY CONTENT PASS check', 2)!
	for name in ['format', 'scope', 'omitted-directory', 'extra-directory', 'omitted-name', 'extra-name', 'unknown-field', 'duplicate-field', 'whitespace'] {
		mut decoded := json2.decode[map[string]json2.Any](sealed)!
		match name {
			'format' { decoded['format'] = json2.Any(0) }
			'scope' { decoded['scope'] = json2.Any('forged') }
			'omitted-directory' { decoded['directories'] = json2.Any(map[string]json2.Any{}) }
			'extra-directory' {
				mut changed := json2.decode[map[string]json2.Any](json2.encode(observed))!; changed['/unlisted'] = json2.Any([]json2.Any{})
				decoded['directories'] = json2.Any(changed)
			}
			'omitted-name', 'extra-name' {
				mut changed := json2.decode[map[string]json2.Any](json2.encode(observed))!
				changed[filled] = json2.decode[json2.Any](json2.encode(if name == 'omitted-name' { []string{} } else { [...observed[filled], '00'] }))!
				decoded['directories'] = json2.Any(changed)
			}
			else { decoded['unknown'] = json2.Any(true) }
		}
		text := if name == 'duplicate-field' { sealed.replace_once('{', '{"format":0,') } else if name == 'whitespace' { sealed + '\n' } else { json2.encode(decoded) + '\n' }
		require(text != sealed, 'forged directory fixture unchanged')!
		path := root + '/' + name + '.json'; os.write_file(path, text)!
		invoke([tool, 'check', manifest, path], root + '/' + name + '.log', false, 'native directory content or declaration differs', 2)!
		passed << name
	}
	os.symlink(filled, root + '/alias')!
	for name, targets in {'empty-targets': []string{}, 'many-targets': []string{len: winedircontent.max_targets + 1, init: empty},
		'duplicate-target': [empty, empty], 'relative-target': ['filled'], 'linked-target': [root + '/alias'],
		'noncanonical-target': [root + '/../' + os.file_name(root) + '/filled'], 'regular-target': [file],
		'fifo-target': [fifo], 'missing-target': [root + '/absent'], 'nul-target': [filled + '\x00suffix']} {
		path := root + '/' + name + '-targets.json'; fresh := root + '/' + name + '-receipt.json'
		os.write_file(path, json2.encode(targets))!
		invoke([tool, 'capture', path, fresh], root + '/' + name + '.log', false, '', 2)!
		require(!os.exists(fresh), 'invalid directory targets published a receipt')!
		passed << name
	}
	for name in ['linked-manifest', 'linked-receipt', 'overwrite', 'linked-output', 'large-manifest', 'large-receipt', 'fifo-manifest', 'fifo-receipt', 'self-output'] {
		path := root + '/' + name
		if name.starts_with('linked-') { os.symlink(if name == 'linked-manifest' { manifest } else { receipt }, path)! }
		if name.starts_with('large-') {
			mut large := os.create(path)!
			require(large.write_to(if name.ends_with('manifest') { u64(1048576) } else { u64(8388608) }, [u8(0)])! == 1, 'large declaration setup failed')!
			large.close()
		}
		if name.starts_with('fifo-') { require(C.mkfifo(path.str, 0o600) == 0, 'declaration FIFO setup failed')! }
		fresh := root + '/' + name + '-fresh.json'
		command := if name.ends_with('manifest') { [tool, 'capture', path, fresh] }
			else if name == 'overwrite' { [tool, 'capture', manifest, receipt] }
			else if name == 'linked-output' { [tool, 'capture', manifest, path] }
			else if name == 'self-output' { [tool, 'capture', manifest, filled + '/must-not-exist'] }
			else { [tool, 'check', manifest, path] }
		invoke(command, root + '/' + name + '.log', false, '', 2)!
		require(!os.exists(fresh) && !os.exists(filled + '/must-not-exist') && os.read_file(receipt)! == sealed, 'publication refusal wrote output')!
		if name.starts_with('fifo-') { os.write_file(root + '/' + name + '-retired.json', json2.encode(os.lstat(path)!))!; os.rm(path)! }
		passed << name
	}
	// Exact native limits and their first rejected increments.
	mut count_dirs := []string{}
	for index in 0 .. 4 {
		path := root + '/count-' + index.str(); os.mkdir(path)!; count_dirs << path
		for number in 0 .. winedircontent.max_entries { os.write_file(path + '/e' + number.str(), '')! }
	}
	count_manifest := root + '/count-targets.json'; count_receipt := root + '/count-receipt.json'
	os.write_file(count_manifest, json2.encode(count_dirs))!
	invoke([tool, 'capture', count_manifest, count_receipt], root + '/count-limit.log', true, 'WINE DIRECTORY CONTENT PASS capture', 10)!
	os.write_file(count_dirs[0] + '/overflow', '')!
	invoke([tool, 'check', count_manifest, count_receipt], root + '/per-directory-bound.log', false, 'directory entry inventory exceeds bound', 10)!
	os.rm(count_dirs[0] + '/overflow')!
	invoke([tool, 'check', count_manifest, count_receipt], root + '/count-restored.log', true, 'WINE DIRECTORY CONTENT PASS check', 10)!
	passed << 'per-directory-bound'
	extra := root + '/count-4'; os.mkdir(extra)!; os.write_file(extra + '/one', '')!
	mut total_dirs := count_dirs.clone(); total_dirs << extra
	os.write_file(root + '/total-targets.json', json2.encode(total_dirs))!
	invoke([tool, 'capture', root + '/total-targets.json', root + '/total-must-not-exist.json'], root + '/total-bound.log', false, 'directory entry inventory exceeds bound', 10)!
	require(!os.exists(root + '/total-must-not-exist.json'), 'entry bound published a receipt')!
	passed << 'total-bound'
	mut byte_dirs := []string{}
	for index in 0 .. 2 {
		path := root + '/bytes-' + index.str(); os.mkdir(path)!; byte_dirs << path
		for number in 0 .. (if index == 0 { 2048 } else { 2064 }) {
			prefix := number.str(); os.write_file(path + '/' + prefix + 'x'.repeat(255 - prefix.len), '')!
		}
	}
	// 4112 * 255 + 16 = 1 MiB exactly.
	os.write_file(byte_dirs[0] + '/1234567890abcdef', '')!
	byte_manifest := root + '/bytes-targets.json'; byte_receipt := root + '/bytes-receipt.json'
	os.write_file(byte_manifest, json2.encode(byte_dirs))!
	invoke([tool, 'capture', byte_manifest, byte_receipt], root + '/bytes-limit.log', true, 'WINE DIRECTORY CONTENT PASS capture', 10)!
	os.write_file(byte_dirs[0] + '/z', '')!
	invoke([tool, 'check', byte_manifest, byte_receipt], root + '/bytes-bound.log', false, 'directory entry inventory exceeds bound', 10)!
	os.rm(byte_dirs[0] + '/z')!
	invoke([tool, 'check', byte_manifest, byte_receipt], root + '/bytes-restored.log', true, 'WINE DIRECTORY CONTENT PASS check', 10)!
	passed << 'name-bytes-bound'
	if os.args.len == 8 {
		builder := os.real_path(os.args[3])
		for index, role in ['fixture', 'controller', 'producer', 'retainer'] {
			host := os.real_path(os.args[index + 4])
			invoke([builder, 'check', host], root + '/' + role + '-before.log', true, 'WINE HOST BUILD ADMISSION PASS', 30)!
			require(json2.decode[Format](os.read_file(host + '/host-build.json')!)!.format == 11
				&& json2.decode[Format](os.read_file(host + '/read-closed/receipt.json')!)!.format == 6, 'original format-11 host graph required')!
			declared := json2.decode[Replay](os.read_file(host + '/read-closed/receipt.json')!)!.directories
			mut unique := map[string]bool{}
			for path in declared { unique[os.real_path(path)] = true }
			mut targets := unique.keys(); targets.sort()
			path := root + '/' + role + '-targets.json'; content := root + '/' + role + '-content.json'
			os.write_file(path, json2.encode(targets))!
			invoke([tool, 'capture', path, content], root + '/' + role + '-capture.log', true, 'WINE DIRECTORY CONTENT PASS capture', 30)!
			invoke([tool, 'check', path, content], root + '/' + role + '-check.log', true, 'WINE DIRECTORY CONTENT PASS check', 30)!
			invoke([builder, 'check', host], root + '/' + role + '-after.log', true, 'WINE HOST BUILD ADMISSION PASS', 30)!
		}
	}
	os.write_file(root + '/retired-entry-fifo.json', json2.encode(os.lstat(fifo)!))!; os.rm(fifo)!
	// The ordinary typed auditor excludes newline path framing. Preserve the
	// exact original name/metadata and retain the node under a safe name.
	special := filled + '/quote"-backslash\\-newline\n'
	os.write_file(root + '/retired-special-entry.json', json2.encode({
		'original_path_hex': special.bytes().hex(),
		'metadata_json': json2.encode(os.lstat(special)!),
		'data_hex': os.read_file(special)!.bytes().hex(),
		'retained_path': root + '/retired-special-entry'
	}))!
	os.rename(special, root + '/retired-special-entry')!
	require(passed.len == 37, 'complete directory control matrix required')!
	os.write_file(root + '/result.json', json2.encode(passed))!
	println('WINE DIRECTORY CONTENT CONTROLS PASS empty/special entries, restored baselines, child independence, exact native limits, ' + passed.len.str() + ' refusals')
}

fn main() {
	if os.args.len > 1 && os.args[1] == 'guards' { guards() or { eprintln(err); exit(1) } }
	else { check() or { eprintln(err); exit(1) } }
}
