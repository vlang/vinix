// SPDX-License-Identifier: BSD-2-Clause
@[has_globals]
module main

import comparecore as b
import evidencearchive as archive
import json2
import os
import reportcore as r
import reportfixture as fixture

fn check_times() ! {
	base := r.utc_time(b.Value('2026-10-02T22:01:48.239890+00:00'), 'test')!
	for text in ['2026-10-02T22:01:48.23989Z', '2026-10-02 22:01:48.2398900-00:00',
		'20261002T220148.239890+0000', '2026-10-02T22:01:48,239890+00:00:00',
		'2026-W40-5T22:01:48.239890Z', '2026W405T220148.239890Z', '2026-10-02🍂22:01:48.239890Z'] {
		assert r.utc_time(b.Value(text), 'test')!.unix_micro() == base.unix_micro()
	}
	for text in ['2026-10-02T22:01:48', 'bad', '2026-02-30T00:00:00Z', '2026-10-02T24:00:00Z',
		'2026-10-02T22:01:60Z', '0000-01-01T00:00:00Z', '2026-10-02T22:01:48+01:00',
		'2026-10-02T22:01:48+00:00garbage', '2026-10-02T22:01:48.1.2Z', '2026-10-02T22:01:48+000:0',
		'2026-W00-1T00:00:00Z', '2026-W53-8T00:00:00Z', '2025-W53-1T00:00:00Z'] {
		mut rejected := false
		r.utc_time(b.Value(text), 'test') or { rejected = true }
		assert rejected, text
	}
	assert r.utc_time(b.Value('2026-10-02T22:01:48.239891Z'), 'test')!.unix_micro() == base.unix_micro() + 1
}

fn reports(root string) ! {
	for campaign in archive.campaigns {
		ctx := r.context(root, root + '/tests/alloc-bench/results/' + campaign, campaign)!
		report := ctx.recompute()!
		actual := json2.decode[b.Value](json2.encode(report))!
		expected := json2.decode[b.Value](os.read_file(ctx.here + '/comparison.json')!)!
		assert b.equal(actual, expected), 'Saved raw observations, statistics or provenance differ: ' + campaign
		saved_markdown := os.read_file(ctx.here + '/comparison.md')!
		// The published v4/v5 documents add a title; their original recompute.py
		// prints the body alone. Preserve both the capture and CLI behavior.
		body := saved_markdown.trim_string_left('# Complete ${ctx.profile.version} allocation comparison\n\n')
		assert report.markdown() == body, 'Saved Markdown differs: ' + campaign
		findings := fixture.suite(ctx)!
		previous := r.object(ctx.here + '/validation/recompute-review.json')!
		old_checks := b.value(previous, 'checks') as []b.Value
		mut names := map[string]bool{}
		for check in findings.checks { names[check.test] = true }
		assert old_checks.len == 170
		for check in old_checks {
			name := b.value(check as map[string]b.Value, 'test') as string
			assert name in names, 'Original integrity case missing: ' + name
		}
		assert findings.check_count == 171
		println('${campaign}: saved JSON/Markdown exact, 171 integrity checks PASS')
	}
}

fn archives(root string) ! {
	data := archive.manifest(root)!
	archive.verify(root, data)!
	temp := fixture.temporary('vinix-evidence-fixture-')!
	defer { os.rmdir_all(temp) or {} }
	selected := data.files.filter(it.storage == 'git-history')[0]
	content := archive.read_source(root, selected.path)!
	out := temp + '/output'
	archive.materialize(root, data, out, [selected.path], '')!
	path := archive.destination(root, out, selected.path)!
	assert os.read_file(path)! == content
	assert os.stat(path)!.mode & 0o777 == if selected.mode == '100755' { 0o755 } else { 0o644 }
	archive.materialize(root, data, out, [selected.path], '')!
	os.write_file(path, 'changed\n')!
	mut rejected := false
	archive.materialize(root, data, out, [selected.path], '') or { rejected = true }
	assert rejected && os.read_file(path)! == 'changed\n'
	for relative in ['../escape', '/absolute', 'a/../escape', 'a//b', './b', 'a\\b', 'a\x00b'] {
		rejected = false
		archive.destination(root, out, relative) or { rejected = true }
		assert rejected, relative
	}
	os.mkdir_all(out + '/safe')!
	os.symlink(root, out + '/safe/checkout')!
	rejected = false
	archive.destination(root, out, 'safe/checkout/forbidden') or { rejected = true }
	assert rejected
	os.symlink(temp, out + '/safe/outside')!
	rejected = false
	archive.destination(root, out, 'safe/outside/forbidden') or { rejected = true }
	assert rejected
	rejected = false
	archive.destination(root, root + '/tests/alloc-bench/nonexistent', 'forbidden') or { rejected = true }
	assert rejected
	// No archive source, log, expected timing, manifest or Python fixture is
	// written here. Binary boundary tests use a synthetic V Git stand-in.
	archive.write_source(root, out, 'binary', 'a\x00b\n\xff', '100755')!
	assert os.read_file(out + '/binary')! == 'a\x00b\n\xff'
	assert os.stat(out + '/binary')!.mode & 0o777 == 0o755
	println('Archive recovery, modes, binary bytes and destination rejection PASS')
}

fn git_standin(mode string) {
	_ := os.get_line()
	match mode {
		'header' { print('bad\n') }
		'missing' { print('missing missing\n') }
		'overflow' { print('${'a'.repeat(40)} blob 18446744073709551616\n') }
		'oversized' { print('${'a'.repeat(40)} blob 268435457\n') }
		'truncated' { print('${'a'.repeat(40)} blob 12\nfour') }
		'newline' { print('${'a'.repeat(40)} blob 4\nfourX') }
		'binary', 'flood' {
			if mode == 'flood' { eprint('e'.repeat(200000)) }
			print('${'a'.repeat(40)} blob 5\na\x00b\nz\n')
		}
		'large' { print('${'a'.repeat(40)} blob 1048576\n' + 'q'.repeat(1048576) + '\n') }
		else { exit(9) }
	}
}

fn protocols(root string) ! {
	temp := fixture.temporary('vinix-git-protocol-')!
	defer { os.rmdir_all(temp) or {} }
	os.symlink(os.executable(), temp + '/git')!
	previous := os.getenv('PATH')
	defer {
		os.setenv('PATH', previous, true)
		os.unsetenv('VINIX_REPORT_GIT_STANDIN')
	}
	os.setenv('PATH', temp + ':' + previous, true)
	for mode in ['header', 'missing', 'overflow', 'oversized', 'truncated', 'newline', 'binary',
		'flood', 'large'] {
		os.setenv('VINIX_REPORT_GIT_STANDIN', mode, true)
		mut reader := archive.reader(root)!
		if mode in ['binary', 'flood', 'large'] {
			blob := reader.read('a'.repeat(40))!
			assert blob.id == 'a'.repeat(40)
			assert blob.content == if mode == 'large' { 'q'.repeat(1048576) } else { 'a\x00b\nz' }
		} else {
			mut rejected := false
			reader.read('a'.repeat(40)) or { rejected = true }
			assert rejected, mode
		}
		reader.close()
		reader.close()
	}
	println('Git framing, EOF, overflow, binary and stderr backpressure PASS')
}

fn main() {
	mode := os.getenv('VINIX_REPORT_GIT_STANDIN')
	if mode != '' && os.args.len > 1 && os.args[1] == 'cat-file' {
		git_standin(mode)
		return
	}
	guard := archive.own_commands()
	defer { guard.close() }
	root := os.real_path(os.dir(@FILE) + '/../..')
	check_times()!
	reports(root)!
	archives(root)!
	protocols(root)!
	println('Native benchmark analysis qualification PASS')
}
