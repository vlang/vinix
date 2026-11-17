// SPDX-License-Identifier: GPL-2.0-or-later
import os
import json2
import crypto.sha256

struct Entry { path string }
struct Manifest { entries []Entry }

fn run(program string, args []string, folder string) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder)
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(out) }; return out
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	assert os.args.len == 4, 'usage: reclaim-cache CURRENT_STATE COMPLETED_TASK_ROOT COMMITTED_REPORT'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[1]); root := os.abs_path(os.args[2])
	assert root.starts_with('/Users/alex/.local/state/vinix/omarchy-m1-') && root != state
	assert os.real_path(root) == root
	completion := os.read_file(root + '/completion.txt')!
	revision := completion.all_after('feature commit ').all_before('\n')
	assert revision.len == 40 && completion.contains('Complete typed inventory receipt: PASS')
	report := run('git', ['show', revision + ':' + os.args[3]], repo)!
	mut receipt := []string{}
	for file in ['inventory.json', 'bundle.tar.gz'] {
		hash := digest(root + '/' + file)!
		assert report.contains(hash) && completion.contains(file + ' sha256 ' + hash)
		receipt << file + ' sha256 ' + hash
	}
	manifest := json2.decode[Manifest](os.read_file(root + '/inventory.json')!)!
	assert manifest.entries.len > 100
	for entry in manifest.entries { assert entry.path != 'tmp' && !entry.path.starts_with('tmp/') }
	receipt << run(root + '/bundle/inventory-check', ['check-inventory', root + '/bundle', root + '/inventory.json'], repo)!.trim_space()
	cache := root + '/tmp'
	assert os.real_path(cache) == cache && !os.is_link(cache)
	for name in os.ls(cache)! {
		if !(name.starts_with('v3_module_cache_') || name == 'v3_thirdparty_objs'
			|| name == 'v3_macos_sdk_root' || name.starts_with('v3_fallback_')) {
			receipt << 'preserved unrecognized entry: ' + name
			continue
		}
		path := cache + '/' + name; assert !os.is_link(path)
		if os.is_dir(path) { os.rmdir_all(path)! } else { os.rm(path)! }
		receipt << 'disposable compiler cache: ' + name
	}
	os.write_file(state + '/reclaimed-' + os.file_name(root) + '.txt', receipt.join('\n') + '\n')!
	println(os.file_name(root) + ': verified committed hashes and complete bundle; removed only excluded compiler cache')
}
