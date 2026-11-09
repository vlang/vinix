// SPDX-License-Identifier: GPL-2.0-or-later
// Generate a separate fixed reuse profile. Never edits the qualified owner.
module main

import crypto.sha256
import json2
import os

const donor = '/Users/alex/code/vinix/build/package-perf-runtime-worktree/tests/desktop-perf/foreground-supervise.v'
const donor_sha = '413a2e8b540169cbcf6a7728105b38044260d5548722cfb40f2d5c4ec523eb1d'
const stage = '/Users/alex/Library/Caches/vinix-codex/section14/perf-runtime-host-20261105-01/reuse-adapter-host-01'

fn pin(path string) !string {
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.size > 512 * 1024 { return error('bounded regular source required') }
	return sha256.hexhash(os.read_file(path)!)
}

fn generate(output string) ! {
	if !output.starts_with(stage + '/') || os.real_path(os.dir(output)) != os.dir(output)
		|| os.exists(output) || os.is_link(output) { return error('fresh canonical output inside fixed host stage required') }
	if pin(donor)! != donor_sha { return error('qualified donor source differs') }
	text := os.read_file(donor)!
	marker := '\nfn main() {'
	if text.count(marker) != 1 || text.count('import crypto.sha256\n') != 1 {
		return error('qualified donor entry/import boundary differs')
	}
	mut before := map[string]string{}
	for relative, embedded in {
		'reuse-source/entry.v': $embed_file('reuse-source/entry.v').to_string()
		'reuseprofile/contract.v': $embed_file('reuseprofile/contract.v').to_string()
		'reuseprofile/controls.v': $embed_file('reuseprofile/controls.v').to_string()
	} {
		path := @DIR + '/' + relative
		before[relative] = pin(path)!
		if before[relative] != sha256.hexhash(embedded) { return error('compiled source input differs: ' + relative) }
	}
	entry := os.read_file(@DIR + '/reuse-source/entry.v')!
	if !entry.starts_with('// SPDX-License-Identifier: GPL-2.0-or-later\n// Appended') || entry.contains('\nmodule ')
		|| entry.contains('\nimport ') || entry.count('\nfn main() {') != 1 {
		return error('fixed reuse entry boundary differs')
	}
	generated := text.all_before(marker).replace_once('import crypto.sha256\n', 'import crypto.sha256\nimport reuseprofile\n') + '\n' + entry
	os.mkdir(output)!
	os.mkdir(output + '/reuseprofile')!
	os.write_file(output + '/main.v', generated)!
	for relative, expected in before {
		source := @DIR + '/' + relative
		name := if relative.starts_with('reuseprofile/') { relative } else { 'entry-source.v.txt' }
		target := output + '/' + name
		os.cp(source, target, fail_if_exists: true)!
		if pin(source)! != expected || pin(target)! != expected { return error('source changed during independent copy') }
	}
	if pin(donor)! != donor_sha { return error('qualified donor changed during generation') }
	os.write_file(output + '/source.json', json2.encode({
		'donor': donor
		'donor_sha256': donor_sha
		'inputs': json2.encode(before)
		'generated_sha256': pin(output + '/main.v')!
		'scope': 'Source generation only. The qualified owner is unchanged; this new fixed entry requires independent compilation and controls.'
	}) + '\n')!
	println('PERF REUSE SOURCE GENERATED ' + pin(output + '/main.v')!)
}

fn main() {
	if os.args.len != 2 { eprintln('usage: prepare-reuse-source NEW_FIXED_HOST_STAGE_DIRECTORY'); exit(2) }
	generate(os.args[1]) or { eprintln(err); exit(1) }
}
