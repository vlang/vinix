// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import hosttest
import json2
import os

pub fn allocation_audit(context Context, baseline bool) !int {
	compiler := context.root + '/build/useralloc-final-audit/compiler/v'
	tree := context.root + '/third_party/' + if baseline { 'useralloc-speed-v5-audit-base' } else { 'useralloc-speed-v5' }
	state := if baseline && context.state == os.dir(context.origin) { context.root + '/build/useralloc-kernel-speed-v5/allocation-audit' } else { context.state }
	command := [hosttest.root() + '/tests/kernel-allocs/run.sh']
	mut env := os.environ()
	env['V'] = compiler
	env['VINIX_KERNEL_ALLOCS_ROOT'] = tree
	log := state + '/' + if baseline { 'baseline.log' } else { 'candidate.log' }
	status := logged(command, log, env, tree, '')!
	if baseline {
		write_json(state + '/baseline-run.json', {
			'command': json2.Any(command.map(json2.Any(it)))
			'environment': json2.Any({'V': json2.Any(compiler), 'VINIX_KERNEL_ALLOCS_ROOT': json2.Any(tree)})
			'exit_code': json2.Any(status)
			'compiler_sha256': json2.Any(digest(compiler)!)
			'allowed_sha256': json2.Any(digest(tree + '/tests/kernel-allocs/allowed.txt')!)
			'finished_utc': json2.Any(now())
			'notes': json2.Any('Exact frozen v4 kernel sources with same fixed checker/full literal allowlist as v5. No allowlist edits.')
		})!
		println(status)
		return 0
	}
	prior := context.root + '/build/useralloc-kernel-speed-v4/allocation-audit/candidate.log'
	base := allocation_report(os.read_bytes(prior)!)
	new := allocation_report(os.read_bytes(log)!)
	deltas := allocation_deltas(base.counts, new.counts)
	manifest := map[string]json2.Any{
		'command': json2.Any(command.map(json2.Any(it)))
		'environment': json2.Any({'V': json2.Any(compiler), 'VINIX_KERNEL_ALLOCS_ROOT': json2.Any(tree)})
		'candidate_exit_code': json2.Any(status)
		'baseline_source': json2.Any('build/useralloc-kernel-speed-v4/allocation-audit/candidate.log')
		'baseline_sites': json2.Any(allocation_total(base.counts))
		'candidate_sites': json2.Any(allocation_total(new.counts))
		'path_kind_deltas': json2.Any(deltas)
		'allocation_site_regression': json2.Any(deltas.values().any(it.int() > 0))
		'reported_architectures': json2.Any(new.architectures)
		'compiler_sha256': json2.Any(digest(compiler)!)
		'notes': json2.Any('Literal unchanged allowlist result retained; compare exact frozen-V e29 baseline without line-number noise. No allowlist edits.')
	}
	write_json(state + '/comparison.json', manifest)!
	println(json2.encode(manifest, prettify: true))
	flush_stdout()
	return 0
}

pub fn capture_allocation_diagnostic(context Context) !int {
	state := if context.state == os.dir(context.origin) { context.root + '/build/useralloc-allocation-audit-final' } else { context.state }
	work := context.root + '/third_party/useralloc-pipe'
	compiler := context.root + '/build/useralloc-final-audit/compiler/v'
	source := state + '/x86-diagnostic-source'
	mkdirs(source)!
	// Capture the exact dry recipe without compiling kernel objects.
	make := captured_at(['make', '-Bn', 'obj/blob.c.o', 'ARCH=x86_64', 'V=' + compiler, 'PROD=false'], work + '/kernel')!
	os.write_file(state + '/x86-diagnostic.make', make)!
	rows := make.split_into_lines().filter(it.starts_with('for f in '))
	if rows.len == 0 { return error('x86 diagnostic source recipe missing') }
	paths := rows[0]['for f in '.len..].all_before(';').fields()
	for name in paths {
		if name.starts_with('/') || '..' in name.split('/') { return error('unsafe diagnostic source path') }
		mkdirs(os.dir(source + '/' + name))!
		hosttest.module_copy_file_preserving_stat(work + '/kernel/' + name, source + '/' + name)!
	}
	hosttest.module_copy_file_preserving_stat(work + '/kernel/v.mod', source + '/v.mod')!
	command := [compiler, '-os', 'vinix', '-enable-globals', '-nofloat', '-manualfree', '-message-limit', '100000', '-gc', 'none', '-target-libc-headers', '-no-closures', '-d', 'no_backtrace', '-arch', 'amd64', '-warn-about-allocs', '-o', state + '/x86-diagnostic.c', source]
	status := logged(command, state + '/x86-diagnostic.log', os.environ(), '', '')!
	write_json(state + '/x86-diagnostic.json', {'command': json2.Any(command.map(json2.Any(it))), 'exit_code': json2.Any(status), 'compiler_sha256': json2.Any(digest(compiler)!), 'source_count': json2.Any(paths.len), 'log_sha256': json2.Any(digest(state + '/x86-diagnostic.log')!), 'note': json2.Any('Exact required audit V command and final source; complete diagnostics retained because normal script filters and removes these.')})!
	println('exit ' + status.str())
	flush_stdout()
	return 0
}
