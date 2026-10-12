// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import cachecli
import comparecore
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand

pub struct CohortPolicy {
pub:
	profile string
	inputs map[string]string
	plan map[string]json2.Any
	command []string
}

fn source_hashes(directory string, mut result map[string]string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_link(path) { continue }
		if os.is_dir(path) { source_hashes(path, mut result)! }
		else if path.ends_with('.v') || path.ends_with('.json') || path.ends_with('.h') {
			result[path] = digest(path)!
		}
	}
}

pub fn native_inputs() !map[string]string {
	mut result := map[string]string{}
	for path in ['tests/native-campaign-tools/campaignhost', 'tests/native-allocation-tools/allocationhost',
		'tests/alloc-bench/comparecore', 'tests/native-guest-tools/guesthost', 'tests/linuxkpi/hosttest',
		'build-support/cachecli', 'build-support/cachekey', 'tools/sourcecommand', 'tools/qmpclient',
		'compat/ios/plist', 'build-support/tarcore', 'build-support/tarstream',
		'tests/native-campaign-tools/coreboot', 'tests/qemu-core/corevm', 'build-support/muslnative',
		'build-support/alpinecore', 'tests/desktop-perf/savedworkflow', 'tests/desktop-perf/perfrunner',
		'tests/desktop-perf/perfconsole', 'tests/desktop-perf/perfreport'] {
		source_hashes(hosttest.root() + '/' + path, mut result)!
	}
	for name in ['main.v', 'core-main.v', 'console-main.v'] {
		result[hosttest.root() + '/tests/native-campaign-tools/' + name] = digest(hosttest.root() + '/tests/native-campaign-tools/' + name)!
	}
	result['native-executable-sha256'] = digest(os.executable())!
	return result
}

pub struct Step {
pub:
	report_name string
	state_name  string
	guest       string
}

pub fn cohort_steps(version string) []Step {
	return [Step{'vinix-1', 'useralloc-vinix-' + version + '-final-1', 'vinix'},
		Step{'catalina-1', 'useralloc-macos-' + version + '-final-1', 'catalina'},
		Step{'catalina-2', 'useralloc-macos-' + version + '-final-2', 'catalina'},
		Step{'vinix-2', 'useralloc-vinix-' + version + '-final-2', 'vinix'}]
}

pub fn cohort_pins(profile string) !map[string]string {
	data := hosttest.decode_json($embed_file('cohort-pins.json').to_string())!.as_map()
	mut result := map[string]string{}
	for path, value in data[profile]!.as_map() { result[path] = value.str() }
	return result
}

pub fn validate_declared(run comparecore.Run, guest string, plan map[string]json2.Any) ! {
	if comparecore.value(run.config, 'source_sha256') != comparecore.Value(plan['source_sha256']!.str()) {
		return error('Benchmark source mismatch ' + run.name)
	}
	flags := comparecore.Value(comparecore.compile_flags.map(comparecore.Value(it)))
	if !comparecore.equal(comparecore.value(run.config, 'compile_flags'), flags) {
		return error('Compiler flags mismatch ' + run.name)
	}
	common := comparecore.decode_config(json2.encode(plan['common_qemu']!))!
	for key, value in common {
		if !comparecore.equal(comparecore.value(run.config, key), value) {
			return error('Declared QEMU mismatch ' + run.name + ' ' + key)
		}
	}
	argv_value := comparecore.value(run.config, 'argv')
	if argv_value !is []comparecore.Value {
		return error('Actual QEMU arguments missing ' + run.name)
	}
	argv := argv_value.map(if it is string { it } else { comparecore.repr(it) })
	for option, key in {
		'-machine': 'machine'
		'-accel':   'accelerator'
		'-cpu':     'cpu'
		'-smp':     'smp'
		'-m':       'memory_mb'
	} {
		position := argv.index(option)
		wanted := common[key]!
		value := if wanted is string {
			wanted
		} else if wanted is comparecore.Number {
			wanted.text
		} else {
			comparecore.repr(wanted)
		}
		if argv.filter(it == option).len != 1 || position < 0 || position + 1 >= argv.len || argv[position + 1] != value {
			return error('Actual QEMU arguments mismatch ' + run.name + ' ' + option)
		}
	}
	for key, value in {
		'platform':       if guest == 'vinix' { 'Vinix' } else { 'Darwin' }
		'release':        if guest == 'vinix' { '0.1.0' } else { '19.6.0' }
		'arch':           'x86_64'
		'compiler':       'gcc'
		'compiler_major': '14'
		'compiler_minor': if guest == 'vinix' { '2' } else { '3' }
		'compiler_patch': '0'
		'iterations':     '200000'
		'samples':        '7'
	} {
		if (run.meta[key] or { '' }) != value {
			return error('Guest metadata mismatch ' + run.name + ' ' + key)
		}
	}
	artifacts := if guest == 'vinix' {
		{
			'kernel_sha256': '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74'
			'libc_sha256':   'ad78977e92f55d85ace71f1ca43bf650d216923ed3cf6650dd29f22c1d70af9d'
			'libc_a_sha256': '8d5c3deee3610c07c3f9bbfaee3b4fed244ef35051c3e2390e4452b13db34ace'
		}
	} else {
		{
			'assembly_sha256': 'ff4f96b50b88ea1482866c7fed1bbc0750d46e47c0f984466332615439136bdd'
			'binary_sha256':   'aed1e90c728e56b77cbff31c62277eb80762b9a0f54b02e815ce581913352b97'
		}
	}
	for key, value in artifacts {
		if comparecore.value(run.config, key) != comparecore.Value(value) {
			return error('Executed ' + if guest == 'vinix' { 'Vinix' } else { 'Catalina' } + ' artifact mismatch ' + key)
		}
	}
}

pub fn validate_capture(state string, name string, guest string, plan map[string]json2.Any, strict bool) !comparecore.Run {
	if !is_zero(read_json(hosttest.replace_suffix(state, '.exit.json'))!['exit_code']!) {
		return error('Actual driver failure ' + name)
	}
	run := comparecore.read_run(state + '/serial.log', state + '/config.json', name)!
	if strict { validate_declared(run, guest, plan)! }
	if run.meta['iterations'] != '200000' || run.meta['samples'] != '7' {
		return error('Wrong final workload count ' + name)
	}
	return run
}

fn historical_pin(context Context, path string, expected string) ! {
	absolute := context.root + '/' + path
	if os.is_file(absolute) {
		checked_hash(absolute, expected)!
		return
	}
	// Retired code pins authenticate immutable original Git objects as data.
	// The native executable is recorded separately; these bytes are never run.
	blob := {
		'e12ec5a8c90cab335c40e68257d596e0a2d0ba9f284b1e4bfe911fffa352dd06': '6db0552c890fe5c3bfe9525b282b5c5ad81b4fa8'
		'146a8318f8f2ad1daccf0409f96f88f492563a584fee896697ed2d58409ebb6c': '403ada6e721bd7662588a971c02d61b865db981f'
		'271a7215f36c5dfcacc133f0fae2e80f5a8bfd9d1445044f4105843eb53681e8': '9a04cf06c8705be4e737128877e8a66eeffa43e1'
		'd649c51d8f599d4d90c2852fc26892dcc5596d9d5f848f3199698ccd12ddfa48': 'd147bcb4c30957c7b9f6208f6d99e05e5e1cfe65'
		'e321a5d856ff9f046b7ad287799c55199a64b04ea9309cbe0a4b8a33259effd1': 'b128b2451e354067125e925b96fe7bdde4188d29'
	}[expected] or { '' }
	if blob != '' && path.ends_with('.py') {
		bytes := captured(['git', '-C', hosttest.root(), 'cat-file', 'blob', blob])!
		if sha256.sum(bytes.bytes()).hex() != expected {
			return error('historical source pin mismatch: ' + path)
		}
		return
	}
	if path == 'tests/alloc-bench/bench.c' && expected == 'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9' {
		bytes := captured(['git', '-C', hosttest.root(), 'show', '5b37c952^:tests/alloc-bench/bench.c'])!
		if sha256.sum(bytes.bytes()).hex() != expected {
			return error('historical benchmark pin mismatch')
		}
		return
	}
	return error('Frozen input missing: ' + path)
}

pub fn run_cohorts(context Context, profile string) !int {
	version := profile.all_before('-')
	inputs := cohort_pins(profile)!
	strict := version == 'v6'
	plan := if strict {
		read_json(context.root + '/tests/alloc-bench/results/2026-10-03-userspace-v6/campaign-plan.json')!
	} else {
		map[string]json2.Any{}
	}
	if strict && read_json(context.root + '/build/useralloc-v6-final-readiness.json')!['status']!.str() != 'PASS' {
		return error('Final gates are incomplete')
	}
	return run_cohort_policy(context, CohortPolicy{profile: profile, inputs: inputs, plan: plan})!
}

pub fn run_cohort_policy(context Context, policy CohortPolicy) !int {
	profile := policy.profile
	version := profile.all_before('-')
	strict := version == 'v6'
	inputs := policy.inputs
	plan := policy.plan
	steps := cohort_steps(version)
	file := context.root + '/build/useralloc-' + version + '-final-cohorts.json'
	native := native_inputs()!
	if profile != 'v4-guard' && os.is_file(file) {
		previous := read_json(file)!
		if 'native_inputs' in previous {
			if previous['native_inputs']!.as_map() != hosttest.string_map(native) {
				return error('Native producer changed since the retained capture prefix')
			}
		}
	}
	mut records := if profile != 'v4-guard' && os.is_file(file) {
		read_json(file)!['captures']!.as_array().clone()
	} else {
		[]json2.Any{}
	}
	if records.len > steps.len { return error('Invalid completed-prefix record') }
	for ordinal, item in records {
		row := item.as_map()
		if row['report_name']!.str() != steps[ordinal].report_name || !is_zero(row['exit_code']!) {
			return error('Invalid completed-prefix record')
		}
		validate_capture(row['state_dir']!.str(), steps[ordinal].report_name, steps[ordinal].guest, plan, strict)!
	}
	for ordinal, step in steps {
		for path, expected in native { checked_hash(if path == 'native-executable-sha256' { os.executable() } else { path }, expected)! }
		for path, expected in inputs { historical_pin(context, path, expected)! }
		if ordinal < records.len { continue }
		state := context.root + '/build/' + step.state_name
		if os.exists(state) || os.is_file(hosttest.replace_suffix(state, '.exit.json')) {
			return error('Refusing existing capture ' + state)
		}
		command := if policy.command.len == 0 {
			[os.executable(), 'cohort-driver', context.origin, '--root', context.root,
				'--state-dir', state, '--version', version, '--guest', step.guest]
		} else { [...policy.command, state, step.guest] }
		started := now()
		println(started + ' starting ' + step.report_name)
		flush_stdout()
		host_before := captured(['ps', '-axo', 'pid,ppid,pcpu,comm'])!
		result := sourcecommand.capture_owned(command, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled, unsafe { nil }, unsafe { nil }, unsafe { nil }, 15)!
		print(result.stdout)
		eprint(result.stderr)
		mut item := map[string]json2.Any{
			'report_name':           json2.Any(step.report_name)
			'state_dir':             json2.Any(state)
			'argv':                  json2.Any(command.map(json2.Any(it)))
			'started_utc':           json2.Any(started)
			'finished_utc':          json2.Any(now())
			'exit_code':             json2.Any(result.status)
			'host_processes_before': json2.Any(host_before)
		}
		records << json2.Any(item.clone())
		write_json(file, {
			'inputs':   json2.Any(hosttest.string_map(inputs))
			'native_inputs': json2.Any(hosttest.string_map(native))
			'captures': json2.Any(records)
		})!
		if result.status != 0 { return result.status }
		run := validate_capture(state, step.report_name, step.guest, plan, strict)!
		item['validation'] = 'Strict complete unchanged six workloads, all 42 samples, checksums and DONE verified.'
		value := comparecore.value(run.config, 'source_sha256')
		if value !is string { return error('benchmark source hash missing') }
		item['source_sha256'] = value
		records[records.len - 1] = json2.Any(item.clone())
		write_json(file, {
			'inputs':   json2.Any(hosttest.string_map(inputs))
			'native_inputs': json2.Any(hosttest.string_map(native))
			'captures': json2.Any(records)
		})!
		println('Complete validated capture ' + step.report_name)
		flush_stdout()
	}
	if strict {
		mut runs := map[string]comparecore.Run{}
		for item in records {
			row := item.as_map()
			name := row['report_name']!.str()
			runs[name] = comparecore.read_run(row['state_dir']!.str() + '/serial.log', row['state_dir']!.str() + '/config.json', name)!
		}
		for number in [1, 2] {
			mismatches, _ := comparecore.comparability(runs['vinix-' + number.str()]!, runs['catalina-' + number.str()]!)
			if mismatches.len > 0 {
				return error('Matched cohort config mismatch: ' + mismatches.str())
			}
		}
	}
	println('All four predeclared fresh captures completed and validated.')
	flush_stdout()
	return 0
}

pub fn cohort_driver(context Context, version string, guest string) !int {
	if version !in ['v4', 'v5', 'v6'] || guest !in ['vinix', 'catalina'] { return error('invalid cohort version or guest') }
	kernel := context.root + '/build/useralloc-kernel-speed-' + if version == 'v4' {
		'v4'
	} else {
		'v5'
	} + '/x86_64/vinix-x86_64'
	command := if guest == 'vinix' {
		[os.executable(), 'allocation-vinix-saved', '--kernel', kernel, '--sysroot',
			context.root + '/third_party/useralloc-libc/build/useralloc/optimized-' + version + '-final',
			'--state-dir', context.state, '--iterations', '200000', '--samples', '7', '--timeout',
			'3600']
	} else {
		[os.executable(), 'allocation-measure', context.state, '--runtime',
			context.root + '/build/useralloc-macos-runtime', '--config',
			context.root + '/tests/alloc-bench/results/2026-10-02/user-macos/config.json']
	}
	started := now()
	status := logged_grace(command, hosttest.replace_suffix(context.state, '.runner.log'), os.environ(), context.root, '', 10)!
	write_json(hosttest.replace_suffix(context.state, '.exit.json'), {
		'argv':         json2.Any(command.map(json2.Any(it)))
		'started_utc':  json2.Any(started)
		'finished_utc': json2.Any(now())
		'exit_code':    json2.Any(status)
	})!
	return status
}
