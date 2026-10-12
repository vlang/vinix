// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import comparecore
import hosttest
import json2
import os

fn retained_cases() ! {
	root := '/Users/alex/code/vinix'
	base := root + '/tests/alloc-bench/results/2026-10-03-userspace-v6'
	plan := campaignhost.read_json(base + '/campaign-plan.json') or { panic(err) }
	for name in ['vinix-1', 'catalina-1', 'catalina-2', 'vinix-2'] {
		guest := if name.starts_with('vinix') { 'vinix' } else { 'catalina' }
		mut run := comparecore.read_run(base + '/' + name + '/serial.log', base + '/' + name + '/config.json', name) or { panic(err) }
		campaignhost.validate_declared(run, guest, plan) or { panic(err) }
		for field in ['source_sha256', 'compile_flags', 'qemu_version', 'machine', 'accelerator',
			'cpu', 'smp', 'memory_mb', 'argv', if guest == 'vinix' {
				'kernel_sha256'
			} else {
				'binary_sha256'
			}] {
			mut altered := run
			altered.config = run.config.clone()
			altered.config[field] = comparecore.Value('invalid independent mutation')
			campaignhost.validate_declared(altered, guest, plan) or { continue }
			panic('declared capture mutation accepted: ' + name + ' ' + field)
		}
		for field in ['platform', 'release', 'arch', 'compiler', 'compiler_major', 'compiler_minor',
			'compiler_patch', 'iterations', 'samples'] {
			mut altered := run
			altered.meta = run.meta.clone()
			altered.meta[field] = 'invalid independent mutation'
			campaignhost.validate_declared(altered, guest, plan) or { continue }
			panic('guest metadata mutation accepted: ' + name + ' ' + field)
		}
	}
	for profile, expected in {
		'v4':       9
		'v4-guard': 9
		'v5':       25
		'v6':       34
	} {
		pins := campaignhost.cohort_pins(profile) or { panic(err) }
		assert pins.len == expected
		steps := campaignhost.cohort_steps(profile.all_before('-'))
		assert steps.map(it.report_name) == ['vinix-1', 'catalina-1', 'catalina-2', 'vinix-2']
	}
	assert campaignhost.is_zero(json2.Any(u64(0)))
	assert !campaignhost.is_zero(json2.Any(u64(4294967296)))
	println('COHORTS / four immutable complete captures / independent config and metadata mutations / exact frozen pin sets and capture order: PASS')
	flush_stdout()
}

fn fixture(root string) !campaignhost.Context {
	os.mkdir(root)!
	os.mkdir(root + '/build')!
	os.write_file(root + '/frozen.txt', 'frozen inputs')!
	return campaignhost.Context{root: root, state: root + '/build', origin: root + '/origin'}
}

fn policy(context campaignhost.Context, mode string) !campaignhost.CohortPolicy {
	return campaignhost.CohortPolicy{profile: 'v4', inputs: {'frozen.txt': campaignhost.digest(context.root + '/frozen.txt')!}, command: [os.executable(), '--capture', mode, context.root]}
}

fn controlled(work string) ! {
	os.mkdir(work)!
	context := fixture(work + '/complete')!
	p := policy(context, 'success')!
	assert campaignhost.run_cohort_policy(context, p)! == 0
	file := context.root + '/build/useralloc-v4-final-cohorts.json'
	records := campaignhost.read_json(file)!
	assert records['captures']!.as_array().map(it.as_map()['report_name']!.str()) == ['vinix-1', 'catalina-1', 'catalina-2', 'vinix-2']
	assert records['native_inputs']!.as_map().len > 0
	assert campaignhost.run_cohort_policy(context, p)! == 0
	assert os.read_file(context.root + '/launches')!.split_into_lines().len == 4
	mut altered := campaignhost.copy_record(records)!
	mut altered_inputs := campaignhost.copy_record(altered['native_inputs']!.as_map())!
	altered_inputs['native-executable-sha256'] = 'changed executable'
	altered['native_inputs'] = altered_inputs.clone()
	hosttest.write_json(file, altered)!
	mut changed_rejected := false
	campaignhost.run_cohort_policy(context, p) or {
		assert err.msg().contains('Native producer changed')
		changed_rejected = true
		hosttest.write_json(file, records)!
		assert os.read_file(context.root + '/launches')!.split_into_lines().len == 4
	}
	assert changed_rejected
	// A failed child is recorded before validation and stops the next launch.
	failed := fixture(work + '/failed')!
	assert campaignhost.run_cohort_policy(failed, policy(failed, 'failure')!)! == 7
	failed_record := campaignhost.read_json(failed.root + '/build/useralloc-v4-final-cohorts.json')!['captures']!.as_array()
	assert failed_record.len == 1 && failed_record[0].as_map()['exit_code']!.int() == 7
	assert os.read_file(failed.root + '/launches')!.split_into_lines().len == 1
	// Keep a completed prefix and resume precisely its two remaining captures.
	resume := fixture(work + '/resume')!
	mut prefix := []json2.Any{}
	for value in records['captures']!.as_array()[..2] {
		mut row := campaignhost.copy_record(value.as_map())!
		source := row['state_dir']!.str()
		state := resume.root + '/build/' + os.base(source)
		os.mkdir(state)!
		for name in ['serial.log', 'config.json'] { os.cp(source + '/' + name, state + '/' + name)! }
		hosttest.write_json(state + '.exit.json', {'exit_code': json2.Any(0)})!
		row['state_dir'] = state
		prefix << json2.Any(row.clone())
	}
	hosttest.write_json(resume.root + '/build/useralloc-v4-final-cohorts.json', {'captures': json2.Any(prefix)})!
	assert campaignhost.run_cohort_policy(resume, policy(resume, 'success')!)! == 0
	assert os.read_file(resume.root + '/launches')!.split_into_lines().len == 2
	for kind in ['existing-state', 'existing-exit', 'bad-prefix', 'bad-log', 'bad-pin'] {
		broken := fixture(work + '/' + kind)!
		first := broken.root + '/build/' + campaignhost.cohort_steps('v4')[0].state_name
		if kind == 'existing-state' { os.mkdir(first)!; os.write_file(first + '/keep', 'keep')! }
		if kind == 'existing-exit' { os.write_file(first + '.exit.json', 'keep')! }
		if kind in ['bad-prefix', 'bad-log'] {
			mut row := campaignhost.copy_record(prefix[0].as_map())!
			if kind == 'bad-prefix' { row['report_name'] = 'catalina-1' }
			if kind == 'bad-log' { row['state_dir'] = broken.root + '/missing' }
			hosttest.write_json(broken.root + '/build/useralloc-v4-final-cohorts.json', {'captures': json2.Any([json2.Any(row.clone())])})!
		}
		original_policy := policy(broken, 'success')!
		if kind == 'bad-pin' { os.write_file(broken.root + '/frozen.txt', 'changed')! }
		campaignhost.run_cohort_policy(broken, original_policy) or {
			assert !os.exists(broken.root + '/launches')
			if kind == 'existing-state' { assert os.read_file(first + '/keep')! == 'keep' }
			if kind == 'existing-exit' { assert os.read_file(first + '.exit.json')! == 'keep' }
			continue
		}
		return error('invalid or protected cohort state accepted: ' + kind)
	}
	println('COHORT OWNER / four actual children / immutable native inputs / no relaunch on complete / exact prefix resume / persisted failure and immediate stop / changed pins and protected state: PASS')
}

fn capture(args []string) !int {
	if args.len != 4 { return error('invalid controlled capture arguments') }
	mode, root, state, guest := args[0], args[1], args[2], args[3]
	mut file := os.open_file(root + '/launches', 'a')!
	file.write_string(guest + '\n')!
	file.close()
	if mode == 'failure' { return 7 }
	os.mkdir(state)!
	base := hosttest.root() + '/tests/alloc-bench/results/2026-10-03-userspace-v6/' + if guest == 'vinix' { 'vinix-1' } else { 'catalina-1' }
	for name in ['serial.log', 'config.json'] { os.cp(base + '/' + name, state + '/' + name)! }
	hosttest.write_json(state + '.exit.json', {'exit_code': json2.Any(0)})!
	return 0
}

fn main() {
	if os.args.len > 1 && os.args[1] == '--capture' { exit(capture(os.args[2..]) or { eprintln(err); 1 }) }
	retained_cases() or { eprintln(err); exit(1) }
	if os.args.len == 2 { controlled(os.args[1]) or { eprintln(err); exit(1) } }
}
