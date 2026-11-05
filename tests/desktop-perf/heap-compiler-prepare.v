// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare an independent compiler source derivation; never build or edit its parent.
module main

import crypto.sha256
import json2
import os
import time

const parent = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain'
const parent_manifest = '/Users/alex/Library/Caches/vinix-codex/section14/perf-heap-producer-target-build-20261104-02/compiler-before/inventory.json'
const manifest_hash = 'ff729f3d39ad09b0401c2f1e08e69784db5c4781117c1f1480a59ee4ffdd39e9'
const compiler_hash = 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
const generator_path = 'vlib/v/gen/c/cleanc.v'
const generator_hash = '55481f6bde34d3cc79458afe7b7c40fbb9716499f5eac29bafd40d00058ee248'
const git = '/Library/Developer/CommandLineTools/usr/bin/git'
const git_hash = '5c5d6527325adcf024e229a9eb540cc0bdd21e1e23ce8f125cf3d8b3704e2659'
const origin = '/Users/alex/code/v'
const revision = '257b514a303f4d302ed23bbac1d51a2ca9624a66'
const bench_tree = '2aa3a53eeac45a276a31f54b96bad192446a7c82'
const old_emission = "\tg.writeln('\\tv3_eprintf(\"%.*s\\\\n\", s.len, (char*)s.str);')"
const new_emission = "\tg.writeln('\\tv3_eprintf(\"%.*s\\\\n\", (int)s.len, (char*)s.str);')"

struct Entry {
	path string
	kind string
	mode u32
	uid u32
	gid u32
	dev u64
	inode u64
	size u64
	mtime i64
	ctime i64
	sha256 string
	target string
}
struct Inventory { format string root string entries []Entry }
struct Pin { path string sha256 string }
struct Counts { mut: entries int files int directories int rounded_bytes u64 }
struct Preparation {
	scope string
	parent string
	parent_manifest_sha256 string
	parent_compiler_sha256 string
	source_revision string
	bench_tree string
	bench_files []Pin
	generator_path string
	generator_before_sha256 string
	generator_after_sha256 string
	independent_files int
	parent_entries int
	copy_rounded_bytes u64
	output string
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn hash(path string) !string {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	return sha256.sum(bytes).hex()
}
fn patch_one(text string) !string {
	require(text.count(old_emission) == 1 && text.count(new_emission) == 0,
		'precision emission must occur exactly once and remain unpatched')!
	return text.replace(old_emission, new_emission)
}

fn bench_pins() []Pin {
	return [
		Pin{'bench.v', '843e47ae449caead69b69fba9c13ed6494e7f06e29ee54012e713504fc1d3cef'},
		Pin{'bench_test.v', 'dc06ee266d23ce105ff7b87cbe6127332a5dea364e6083395ea801d08b21d230'},
		Pin{'limit_memory_darwin.c.v', 'f9a4eb4722a66e60c16a0eb2bbaae2ac71d65c11f1b285cab3863c0f79e92e4f'},
		Pin{'limit_memory_default.c.v', '458439020a490e4d62203d01adcd977cdea9715b5c1792c31e5e0d20c47a6997'},
		Pin{'memory_limit_exit.c.v', '0eef09c3d1fc0beab0765365e04f227f8617a1e3327f922c483e8af9ae8959b9'},
		Pin{'memory_limit_exit_test.v', 'f14f2ee6ad8cdff6cf7d5296ca4f33f44ef9ed6074c728b4176d65525649b198'},
		Pin{'peak_rss.c', '680a3f3f8b3e160e4db47b9a4359e6fb8888abab423c0fb277e7d79f4c6ba840'},
		Pin{'peak_rss.h', '18c4805e286a69c7d69e6036bb1aaf2348225bd7c025ebf9c476d0ab0d0d7cf0'},
		Pin{'peak_rss_default.c.v', '120f6014d7db6e1a86f1972b7aed3643e0dedd70953f31006e401de22e3ebb23'},
		Pin{'peak_rss_nix.c.v', '1046e1b4cdcfb090a8f57fed8b60db2e4ddb0b3efafef228d0b1960139d33ecb'},
	]
}
fn git_read(args []string) !string {
	mut process := os.new_process(git)
	defer { process.close() }
	process.set_args(['-C', origin, ...args])
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	diagnostic := process.stderr_slurp()
	process.wait()
	require(process.code == 0 && diagnostic == '', 'pinned Git object read failed')!
	return output
}
fn safe_path(path string) bool {
	if path == '.' { return true }
	if path.len == 0 || path.starts_with('/') || path.contains('\x00') { return false }
	for part in path.split('/') { if part in ['', '.', '..'] { return false } }
	return true
}
fn walk(root string, relative string, expected map[string]Entry, original bool, start i64,
	mut counts Counts) ! {
	require(time.sys_mono_now() - start < 300 * time.second && counts.entries < 10000,
		'bounded compiler tree inspection exceeded')!
	require(relative in expected, 'unexpected compiler tree entry: ' + relative)!
	entry := expected[relative]
	path := if relative == '.' { root } else { root + '/' + relative }
	require(!os.is_link(path), 'compiler tree link refused: ' + relative)!
	stat := os.lstat(path)!
	require(stat.mode == entry.mode, 'compiler entry mode differs: ' + relative)!
	if original {
		require(stat.uid == entry.uid && stat.gid == entry.gid && stat.dev == entry.dev
			&& stat.inode == entry.inode && stat.mtime == entry.mtime && stat.ctime == entry.ctime,
			'parent literal compiler identity differs: ' + relative)!
	}
	counts.entries++
	if entry.kind == 'directory' {
		require(os.is_dir(path), 'compiler directory differs: ' + relative)!
		counts.directories++
		mut names := os.ls(path)!; names.sort()
		for name in names {
			walk(root, if relative == '.' { name } else { relative + '/' + name },
				expected, original, start, mut counts)!
		}
	} else {
		require(entry.kind == 'file' && os.is_file(path) && stat.size == entry.size
			&& stat.size <= u64(64) << 20 && hash(path)! == entry.sha256,
			'compiler file differs: ' + relative)!
		if !original {
			require(stat.nlink == 1 && (stat.dev != entry.dev || stat.inode != entry.inode),
				'compiler copy aliases its parent: ' + relative)!
		}
		counts.files++
		counts.rounded_bytes += (stat.size + 4095) / 4096 * 4096
		require(counts.rounded_bytes <= u64(256) << 20, 'compiler copy projection exceeded')!
	}
}
fn check(root string, expected map[string]Entry, original bool) !Counts {
	mut counts := Counts{}
	walk(root, '.', expected, original, time.sys_mono_now(), mut counts)!
	require(counts.entries == expected.len, 'compiler tree omits expected entries')!
	return counts
}
fn derived_entries(expected map[string]Entry, out string, patched string) !map[string]Entry {
	mut derived := expected.clone()
	old := derived[generator_path]
	derived[generator_path] = Entry{...old, size: u64(patched.len), sha256: sha256.hexhash(patched)}
	derived['vlib/v/bench'] = Entry{path: 'vlib/v/bench', kind: 'directory', mode: 0o40755}
	for pin in bench_pins() {
		path := 'vlib/v/bench/' + pin.path
		stat := os.lstat(out + '/' + path)!
		derived[path] = Entry{path: path, kind: 'file', mode: 0o100644, size: stat.size, sha256: pin.sha256}
	}
	return derived
}

fn prepare(state string) ! {
	require(state.starts_with('/Users/alex/Library/Caches/vinix-codex/section14/')
		&& state == os.real_path(state) && os.is_dir(state) && state != parent
		&& !state.starts_with(parent + '/') && !parent.starts_with(state + '/'),
		'requires independent canonical existing state directory')!
	out := state + '/toolchain'
	receipt := state + '/preparation.json'
	require(!os.exists(out) && !os.is_link(out) && !os.exists(receipt) && !os.is_link(receipt),
		'preparation output must be fresh')!
	require(hash(parent_manifest)! == manifest_hash && hash(parent + '/v')! == compiler_hash
		&& hash(parent + '/' + generator_path)! == generator_hash && hash(git)! == git_hash,
		'parent manifest, compiler, generator or Git differs')!
	inventory := json2.decode[Inventory](os.read_file(parent_manifest)!)!
	require(inventory.format == 'frame-page-state-v1' && inventory.root == parent
		&& inventory.entries.len == 4636, 'complete parent manifest differs')!
	mut expected := map[string]Entry{}
	for entry in inventory.entries {
		require(safe_path(entry.path) && entry.path !in expected
			&& entry.kind in ['file', 'directory'], 'unsafe or repeated parent entry')!
		expected[entry.path] = entry
	}
	counts := check(parent, expected, true)!
	require(counts.files == 3728 && counts.directories == 908,
		'complete parent entry counts differ')!
	require(git_read(['rev-parse', revision + ':vlib/v/bench'])!.trim_space() == bench_tree,
		'historical bench tree differs')!
	names := bench_pins().map(it.path).join('\n') + '\n'
	require(git_read(['ls-tree', '--name-only', bench_tree])! == names,
		'complete historical bench entry set differs')!
	for path in ['vlib/v/driver/driver.v', generator_path, 'vlib/v/v.v'] {
		require(sha256.hexhash(git_read(['show', revision + ':' + path])!) == hash(parent + '/' + path)!,
			'historical compiler source anchor differs: ' + path)!
	}
	require(!os.exists(parent + '/vlib/v/bench'), 'parent now contains the historical adjunct')!
	os.mkdir(out, mode: 0o700)!
	// Parent-first manifest order is pinned; every ordinary file gets a new inode.
	for entry in inventory.entries {
		if entry.path == '.' { continue }
		path := out + '/' + entry.path
		if entry.kind == 'directory' { os.mkdir(path)! }
		else { os.cp(parent + '/' + entry.path, path)! }
		os.chmod(path, int(entry.mode & 0o7777))!
	}
	os.chmod(out, int(expected['.'].mode & 0o7777))!
	check(out, expected, false)!
	bench := out + '/vlib/v/bench'
	os.mkdir(bench, mode: 0o755)!
	for pin in bench_pins() {
		text := git_read(['show', revision + ':vlib/v/bench/' + pin.path])!
		require(sha256.hexhash(text) == pin.sha256, 'historical bench file differs: ' + pin.path)!
		os.write_file(bench + '/' + pin.path, text)!
		os.chmod(bench + '/' + pin.path, 0o644)!
		require(hash(bench + '/' + pin.path)! == pin.sha256, 'exported bench file differs')!
	}
	text := os.read_file(out + '/' + generator_path)!
	require(sha256.hexhash(text) == generator_hash, 'copied C generator differs')!
	patched := patch_one(text)!
	os.write_file(out + '/' + generator_path, patched)!
	derived := derived_entries(expected, out, patched)!
	final := check(out, derived, false)!
	check(parent, expected, true)!
	require(hash(parent_manifest)! == manifest_hash && hash(git)! == git_hash,
		'parent inventory or selected Git changed during preparation')!
	os.write_file(receipt, json2.encode(Preparation{
		scope: 'Independent source preparation only; C-only bootstrap and strict qualification remain pending.'
		parent: parent
		parent_manifest_sha256: manifest_hash
		parent_compiler_sha256: compiler_hash
		source_revision: revision
		bench_tree: bench_tree
		bench_files: bench_pins()
		generator_path: generator_path
		generator_before_sha256: generator_hash
		generator_after_sha256: sha256.hexhash(patched)
		independent_files: final.files
		parent_entries: counts.entries
		copy_rounded_bytes: counts.rounded_bytes + u64(counts.directories) * 4096 + 61440
		output: out
	}, prettify: true) + '\n')!
	println('HEAP COMPILER independent parent copy, exact historical bench adjunct, single precision cast PASS')
}
fn verify(state string, next_pin string) ! {
	require(state.starts_with('/Users/alex/Library/Caches/vinix-codex/section14/')
		&& state == os.real_path(state) && next_pin.len == 64, 'invalid derived compiler verification')!
	for byte in next_pin {
		require((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`), 'invalid compiler hash')!
	}
	require(hash(parent_manifest)! == manifest_hash && hash(parent + '/' + generator_path)! == generator_hash,
		'parent manifest or generator differs')!
	inventory := json2.decode[Inventory](os.read_file(parent_manifest)!)!
	mut expected := map[string]Entry{}
	for entry in inventory.entries { expected[entry.path] = entry }
	check(parent, expected, true)!
	patched := patch_one(os.read_file(parent + '/' + generator_path)!)!
	out := state + '/toolchain'
	mut derived := derived_entries(expected, out, patched)!
	stat := os.lstat(out + '/v-next')!
	derived['v-next'] = Entry{path: 'v-next', kind: 'file', mode: 0o100755, size: stat.size, sha256: next_pin}
	check(out, derived, false)!
	check(parent, expected, true)!
	println('HEAP COMPILER exact derived sources, pinned new compiler and unchanged parent PASS')
}
fn selfcheck() ! {
	fixture := 'before\n' + old_emission + '\nafter\n'
	require(patch_one(fixture)! == 'before\n' + new_emission + '\nafter\n', 'patch golden output differs')!
	mut refused := 0
	for invalid in ['', old_emission + old_emission, new_emission, old_emission + new_emission] {
		patch_one(invalid) or { refused++; continue }
		return error('malformed patch input was accepted')
	}
	require(refused == 4 && safe_path('.') && safe_path('vlib/v/gen/c/cleanc.v')
		&& !safe_path('../escape') && !safe_path('/absolute') && !safe_path('a//b')
		&& !safe_path('a/./b') && !safe_path('a/../b'), 'preparer selfcheck differs')!
	println('HEAP COMPILER patch golden, four malformed inputs and path controls PASS')
}
fn main() {
	if os.args.len == 2 && os.args[1] == 'selfcheck' {
		selfcheck() or { eprintln(err.msg()); exit(1) }
	} else if os.args.len == 3 && os.args[1] == 'prepare' {
		prepare(os.args[2]) or { eprintln(err.msg()); exit(1) }
	} else if os.args.len == 4 && os.args[1] == 'verify' {
		verify(os.args[2], os.args[3]) or { eprintln(err.msg()); exit(1) }
	} else {
		eprintln('usage: heap-compiler-prepare selfcheck | prepare ABSOLUTE_STATE | verify ABSOLUTE_STATE COMPILER_SHA256')
		exit(2)
	}
}
