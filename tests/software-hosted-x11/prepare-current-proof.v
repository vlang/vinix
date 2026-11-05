// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed first-proof source preparation only; no compiler or process owner.
module main

import crypto.sha256
import json2
import os
import proof

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const suite = state + '/source/tests/software-hosted-x11'
const consumer = state + '/native-consumer-tools-01'
const frozen = consumer + '/current-profile-draft-01'
const capture = consumer + '/source-before-current-01'
const output = consumer + '/current-proof-setup-01'
const base_sha = '558e3d949d310b54d8550bb8d51bbabfab395655f58afdb6167bf1f42fc58f80'
const module_map_sha = '7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce'
const file_limit = u64(1024 * 1024)

struct CaptureTree {
	root string
	entries map[string]string
}

struct CaptureSnapshot {
	files map[string]string
	modes map[string]u32
	trees []CaptureTree
	bytes u64
	entries int
}

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn same(a os.Stat, b os.Stat) bool {
	return a.dev == b.dev && a.inode == b.inode && a.mode == b.mode && a.uid == b.uid
		&& a.gid == b.gid && a.nlink == b.nlink && a.size == b.size
		&& a.mtime == b.mtime && a.ctime == b.ctime
}

fn text(path string) !string {
	before := os.lstat(path)!
	need(os.is_abs_path(path) && os.real_path(path) == path
		&& before.mode & 0o170000 == 0o100000 && before.size <= file_limit,
		'requires a canonical ordinary input at most1MiB: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut bytes := []u8{cap: int(before.size)}
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		need(u64(bytes.len + n) <= file_limit, 'input grew beyond1MiB')!
		bytes << buffer[..n]
	}
	need(u64(bytes.len) == before.size && same(before, os.lstat(path)!), 'input changed during read')!
	return bytes.bytestr()
}

fn pin(path string, wanted string, mut inputs map[string]string) ! {
	need(sha256.hexhash(text(path)!) == wanted, 'fixed source input differs: ' + path)!
	if path in inputs { need(inputs[path] == wanted, 'contradictory source input pin')! }
	inputs[path] = wanted
}

fn fresh(path string) ! { need(!os.exists(path) && !os.is_link(path), 'requires new source output: ' + path)! }

fn ordinary_directory(path string) ! {
	need(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
		'requires an ordinary canonical directory: ' + path)!
}

fn no_omitted_git(path string) ! {
	need(!os.exists(path + '/.git') && !os.is_link(path + '/.git'),
		'unexpected .git entry omitted by the historical source reader')!
}

fn replace_exact(value string, before string, after string, count int) !string {
	need(before != after && value.count(before) == count, 'fixed replacement count differs')!
	changed := value.replace(before, after)
	need(changed.replace(after, before) == value, 'fixed replacement inverse differs')!
	return changed
}

fn full_diff(before string, after string, name string) string {
	old_lines := before.trim_right('\n').split('\n')
	new_lines := after.trim_right('\n').split('\n')
	return '--- frozen/' + name + '\n+++ candidate/' + name + '\n@@ -1,' + old_lines.len.str()
		+ ' +1,' + new_lines.len.str() + ' @@\n' + old_lines.map('-' + it).join('\n')
		+ '\n' + new_lines.map('+' + it).join('\n') + '\n'
}

fn relative(name string) ! {
	need(name != '' && !name.starts_with('/') && !name.contains('\\')
		&& !name.bytes().any(it < 32 || it == 127)
		&& name.split('/').all(it !in ['', '.', '..']), 'invalid fixed source component')!
}

fn frozen_inputs(mut inputs map[string]string) ! {
	ordinary_directory(frozen)!
	manifest := frozen + '/SHA256SUMS'
	pin(manifest, 'f5d5134d7c4e294aab792da798c389b7c909b519124806f1b7b8628d100ccd69', mut inputs)!
	expected_names := ['README.md', 'compactproof/README.md', 'compactproof/QUALIFICATION.md',
		'compactproof/admit.v', 'compactproof/admit_test.v', 'compactproof/controls.v',
		'compactproof/check/main.v', 'compactproof/current.v', 'compactproof/current_controls.v',
		'compactproof/currentcheck/main.v', 'preparation/bind-options-compact.v',
		'preparation/prepare-options-compact.v']
	mut expected := map[string]string{}
	for line in text(manifest)!.split_into_lines() {
		fields := line.split('  ')
		need(fields.len == 2 && fields[0].len == 64
			&& fields[0].bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
			&& fields[1] in expected_names && fields[1] !in expected, 'frozen12-file manifest differs')!
		relative(fields[1])!
		expected[fields[1]] = fields[0]
		pin(frozen + '/' + fields[1], fields[0], mut inputs)!
	}
	need(expected.len == 12, 'frozen source manifest is incomplete')!
	for name in ['compactproof', 'compactproof/check', 'compactproof/currentcheck', 'preparation'] {
		expected[name] = 'directory'
	}
	mut actual := proof.tree(frozen, false)!
	actual.delete('SHA256SUMS')
	need(actual == expected, 'complete frozen source package differs')!
	no_omitted_git(frozen)!
	for name, value in expected { if value == 'directory' { no_omitted_git(frozen + '/' + name)! } }
	for path, hash in {
		capture + '/result.json': '01fd31eb692bf53b94e435df2ee20f05410312c5104444284db06f8b8bb5663b'
		capture + '/mapping.json': '79a09c723f8bfb30a57b773576405bf9849544da6fb0882574e86e919b5297e6'
		capture + '/sources-before.json': '16fe3075ad4a6b39241a3f034848bb0622ec5b17aa42f96958788fddae407b9e'
		capture + '/sources-after.json': '16fe3075ad4a6b39241a3f034848bb0622ec5b17aa42f96958788fddae407b9e'
		capture + '/capture-tree.json': '7f1ab6f14fbf79e905b397b9b8b55c6f6e9b5c0591848ae292f228102104d464'
	} { pin(path, hash, mut inputs)! }
}

fn module_trees() !map[string]string {
	mut result := map[string]string{}
	for name in ['proof', 'launchproof', 'optionsfixture', 'compactproof', 'compactui'] {
		root := suite + '/' + name
		ordinary_directory(root)!
		no_omitted_git(root)!
		tree := proof.tree(root, false)!
		need(tree.len > 0 && tree.len < 64, 'complete fixture module bound differs')!
		for relative, hash in tree {
			if hash == 'directory' { no_omitted_git(root + '/' + relative)!; continue }
			need(hash.len == 64, 'fixture source alias or special file refused')!
			text(root + '/' + relative)!
		}
		result[root] = json2.encode(tree)
	}
	return result
}

fn module_sources(trees map[string]string) !map[string]string {
	mut result := map[string]string{}
	for root, value in trees {
		for name, hash in json2.decode[map[string]string](value, strict: true)! {
			if hash == 'directory' { continue }
			need(name.ends_with('.v'), 'unexpected non-V source in qualified module')!
			result[root + '/' + name] = hash
		}
	}
	need(result.len <= 64, 'full module source bound differs')!
	return result
}

fn copy_one(source string, destination string) ! {
	fresh(destination)!
	before := os.lstat(source)!
	value := text(source)!
	os.cp(source, destination)!
	os.chmod(destination, int(before.mode & 0o7777))!
	after := os.lstat(destination)!
	need(after.nlink == 1 && after.mode == before.mode && text(destination)! == value
		&& same(before, os.lstat(source)!), 'ordinary independent source copy differs')!
}

fn copy_modules(trees map[string]string) !map[string]string {
	mut copies := map[string]string{}
	os.mkdir(output + '/modules-before', mode: 0o700)!
	for root, value in trees {
		name := os.base(root)
		destination := output + '/modules-before/' + name
		os.cp_all(root, destination, false)!
		expected := json2.decode[map[string]string](value, strict: true)!
		need(proof.tree(destination, false)! == expected, 'complete source module copy differs')!
		for relative, hash in expected {
			if hash == 'directory' { continue }
			original := os.lstat(root + '/' + relative)!
			os.chmod(destination + '/' + relative, int(original.mode & 0o7777))!
			copied := os.lstat(destination + '/' + relative)!
			need(copied.nlink == 1 && copied.mode == original.mode
				&& sha256.hexhash(text(destination + '/' + relative)!) == hash,
				'copied qualified source mode/link count differs')!
			copies[destination + '/' + relative] = hash
		}
	}
	return copies
}

fn factor_current(value string) !string {
	header := 'pub fn recorded_current_assembled(desktop string, stage string, arch string, compiler string,\n'
		+ '\tbefore_record string, before_sha256 string, after_record string, after_sha256 string) !map[string]string {\n'
	guards := '\tneed(before_record != after_record, \'distinct current producer pre/post records required\')!\n'
		+ '\tpin(before_record, before_sha256, time.sys_mono_now())!\n'
		+ '\tpin(after_record, after_sha256, time.sys_mono_now())!\n'
		+ '\tbefore := current_recorded_inputs(before_record)!\n'
		+ '\tafter := current_recorded_inputs(after_record)!\n'
		+ '\tfor name, path in before {\n'
		+ '\t\tif name.starts_with(\'audit/\') { need(path != after[name], \'current producer reused an audit output path\')! }\n'
		+ '\t}\n'
	helper := 'fn current_record_pair(before_record string, before_sha256 string, after_record string, after_sha256 string) !(map[string]string, map[string]string) {\n'
		+ guards + '\treturn before, after\n}\n\n'
	delegation := '\tbefore, after := current_record_pair(before_record, before_sha256, after_record, after_sha256)!\n'
	return replace_exact(value, header + guards, helper + header + delegation, 1)
}

fn factor_controls(value string) !string {
	mut result := value
	for arguments in ["path, producer_hash, path, producer_hash", "path, '0'.repeat(64), output + '/different-record', producer_hash"] {
		before := "recorded_current_assembled('/unconsumed-desktop', '/unconsumed-stage', 'aarch64',\n\t\t'/unconsumed-compiler', " + arguments + ')'
		after := 'current_record_pair(' + arguments + ')'
		result = replace_exact(result, before, after, 1)!
	}
	return result
}

fn run() ! {
	$if prod {} $else { return error('requires production embedded source binding') }
	need(os.args == [os.executable(), '--prepare'], 'requires exact --prepare')!
	bound := sha256.hexhash($embed_file('prepare-current-proof.v').to_string())
	need(sha256.hexhash(text(@FILE)!) == bound, 'compiled preparer source changed')!
	ordinary_directory(consumer)!
	ordinary_directory(suite)!
	fresh(output)!
	for name in ['current.v', 'current_controls.v', 'currentcheck'] { fresh(suite + '/compactproof/' + name)! }
	mut inputs := map[string]string{}
	pin(@FILE, bound, mut inputs)!
	pin(repository + '/tests/software-hosted-x11/prepare-current-proof.v', bound, mut inputs)!
	pin(os.executable(), sha256.hexhash(text(os.executable())!), mut inputs)!
	frozen_inputs(mut inputs)!
	snapshot := json2.decode[CaptureSnapshot](text(capture + '/sources-before.json')!, strict: true)!
	need(sha256.hexhash(proof.source()) == snapshot.files[suite + '/proof/admit.v'],
		'compiled historical source reader differs from the preserved private input')!
	before_trees := module_trees()!
	need(snapshot.trees.len == 5, 'historical complete module capture differs')!
	for tree in snapshot.trees {
		need(json2.decode[map[string]string](before_trees[tree.root], strict: true)! == tree.entries,
			'private module differs from preserved historical source')!
	}
	before := module_sources(before_trees)!
	old_map := state + '/native-supervision-host-01/check-02.monitor/modules-before.json'
	pin(old_map, module_map_sha, mut inputs)!
	old_map_text := text(old_map)!
	need(before == json2.decode[map[string]string](old_map_text, strict: true)!, 'qualified five-module source map differs')!
	for path, hash in before {
		need(snapshot.files[path] == hash && os.lstat(path)!.mode == snapshot.modes[path]
			&& os.lstat(path)!.nlink == 1, 'old private source mode/identity differs')!
	}
	for name in ['check.v', 'retain.v', 'evidence-check.v', 'run-native06.v', 'run-evidence06.v',
		'build-supervision-consumer-01.v', 'nativeguard/guard.v', 'diagnostics/recoveryguard/recoveryguard.v'] {
		pin(suite + '/' + name, snapshot.files[suite + '/' + name], mut inputs)!
	}
	flat := suite + '/compactproof-check.v'
	pin(flat, '0c5eeacdfe5dab36ce10182fcd8987689661c6bdb7d83517e0fd7b78f940cc32', mut inputs)!
	need(os.lstat(flat)!.nlink == 1, 'flat checker must be an independent ordinary source')!
	frozen_current := text(frozen + '/compactproof/current.v')!
	frozen_controls := text(frozen + '/compactproof/current_controls.v')!
	entry := text(frozen + '/compactproof/currentcheck/main.v')!
	candidate_current := factor_current(frozen_current)!
	candidate_controls := factor_controls(frozen_controls)!
	need(sha256.hexhash(text(suite + '/compactproof/admit.v')!) == base_sha, 'historical admission source differs')!
	os.mkdir(output, mode: 0o700)!
	copy_one(@FILE, output + '/preparer-source.v')!
	copied := copy_modules(before_trees)!
	copy_one(flat, output + '/flat-checker-before.v')!
	for name in ['current.v', 'current_controls.v'] {
		copy_one(frozen + '/compactproof/' + name, output + '/frozen-' + name)!
		copy_one(frozen + '/compactproof/' + name, suite + '/compactproof/' + name)!
	}
	os.mkdir(suite + '/compactproof/currentcheck', mode: 0o700)!
	copy_one(frozen + '/compactproof/currentcheck/main.v', suite + '/compactproof/currentcheck/main.v')!
	os.write_file(output + '/candidate-current.v', candidate_current)!
	os.write_file(output + '/candidate-current_controls.v', candidate_controls)!
	os.write_file(output + '/current.diff', full_diff(frozen_current, candidate_current, 'current.v'))!
	os.write_file(output + '/current-controls.diff', full_diff(frozen_controls, candidate_controls, 'current_controls.v'))!
	os.write_file(output + '/flat-checker.diff', full_diff(text(flat)!, entry, 'compactproof-check.v'))!
	os.write_file(suite + '/compactproof/current.v', candidate_current)!
	os.write_file(suite + '/compactproof/current_controls.v', candidate_controls)!
	os.write_file(flat, entry)!
	mut expected := before.clone()
	expected[suite + '/compactproof/current.v'] = sha256.hexhash(candidate_current)
	expected[suite + '/compactproof/current_controls.v'] = sha256.hexhash(candidate_controls)
	expected[suite + '/compactproof/currentcheck/main.v'] = sha256.hexhash(entry)
	after_trees := module_trees()!
	after := module_sources(after_trees)!
	need(after == expected, 'complete prepared module source map differs')!
	for root, old_text in before_trees {
		mut wanted := json2.decode[map[string]string](old_text, strict: true)!
		if root == suite + '/compactproof' {
			wanted['current.v'] = sha256.hexhash(candidate_current)
			wanted['current_controls.v'] = sha256.hexhash(candidate_controls)
			wanted['currentcheck'] = 'directory'
			wanted['currentcheck/main.v'] = sha256.hexhash(entry)
		}
		need(json2.decode[map[string]string](after_trees[root], strict: true)! == wanted,
			'complete module namespace differs after preparation')!
	}
	for path, hash in before {
		need(sha256.hexhash(text(path)!) == hash && os.lstat(path)!.mode == snapshot.modes[path]
			&& os.lstat(path)!.nlink == 1, 'qualified historical source changed')!
	}
	for path, hash in copied {
		original := suite + '/' + path[(output + '/modules-before/').len..]
		need(sha256.hexhash(text(path)!) == hash && os.lstat(path)!.nlink == 1
			&& os.lstat(path)!.mode == snapshot.modes[original], 'source preservation copy changed')!
	}
	for root, value in before_trees {
		need(proof.tree(output + '/modules-before/' + os.base(root), false)!
			== json2.decode[map[string]string](value, strict: true)!, 'complete preserved module namespace changed')!
	}
	need(sha256.hexhash(text(output + '/flat-checker-before.v')!) == inputs[flat]
		&& os.lstat(output + '/flat-checker-before.v')!.mode == snapshot.modes[flat]
		&& os.lstat(output + '/flat-checker-before.v')!.nlink == 1, 'preserved original flat checker changed')!
	for path, hash in expected {
		need(sha256.hexhash(text(path)!) == hash && os.lstat(path)!.nlink == 1,
			'prepared source is not an independent ordinary copy')!
	}
	for name in ['current.v', 'current_controls.v', 'currentcheck/main.v'] {
		need(os.lstat(suite + '/compactproof/' + name)!.mode == os.lstat(frozen + '/compactproof/' + name)!.mode,
			'new candidate mode differs from its ordinary source copy')!
	}
	need(text(flat)! == entry && os.lstat(flat)!.mode == snapshot.modes[flat] && os.lstat(flat)!.nlink == 1,
		'new flat checker bytes/mode/link count differ')!
	frozen_inputs(mut inputs)!
	for path, hash in inputs {
		if path == flat { continue }
		need(sha256.hexhash(text(path)!) == hash, 'fixed source input changed during preparation')!
	}
	os.write_file(output + '/modules-before.json', old_map_text)!
	os.write_file(output + '/modules-after.json', json2.encode(after))!
	os.write_file(output + '/module-trees-before.json', json2.encode(before_trees) + '\n')!
	os.write_file(output + '/module-trees-after.json', json2.encode(after_trees) + '\n')!
	os.write_file(output + '/inputs-before.json', json2.encode(inputs) + '\n')!
	os.write_file(output + '/copied-sources.json', json2.encode(copied) + '\n')!
	os.write_file(output + '/flat-checker-binding.json', json2.encode({
		'source': flat, 'before_sha256': inputs[flat], 'before_capture': output + '/flat-checker-before.v',
		'after_sha256': sha256.hexhash(entry), 'scope': 'Intentional flat entry replacement; original bytes retained independently.'
	}) + '\n')!
	os.write_file(output + '/result.json', json2.encode({
		'outcome': 'PREPARED_SOURCE', 'preparer_sha256': bound,
		'base_sha256': base_sha, 'current_sha256': sha256.hexhash(candidate_current),
		'controls_sha256': sha256.hexhash(candidate_controls), 'entry_sha256': sha256.hexhash(entry),
		'before_module_map_sha256': sha256.hexhash(old_map_text),
		'after_module_map_sha256': sha256.hexhash(json2.encode(after)),
		'scope': 'First-proof private source copies and exact factor only. Existing five-module files unchanged; three additive candidates and one preserved flat-entry replacement. No controller/retainer/evidence/wrapper changes, compiler, owner, audit, import or guest.'
	}) + '\n')!
	println('PREPARED private current proof candidate and flat entry; no compiler, audit or guest')
}

fn main() { run() or { eprintln(err); exit(1) } }
