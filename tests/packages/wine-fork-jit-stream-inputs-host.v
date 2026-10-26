// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed host build/unit/preflight runner. Bootstrap is observed outside its own
// guard; every subsequent child is an explicitly selected bounded tool group.
module main

import crypto.sha256
import json2
import os
import tools.packages.winejitstream

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'
const compiler_sha = 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
const clang = '/opt/homebrew/opt/llvm/bin/clang'
const old_bytes = u64(7638328)

struct Step {
	argv       []string
	free_kib   u64
	run        winejitstream.NativeRun
	output_pin string
	assertion_sentinel bool
}

struct Binding {
	entries int
	digest  string
}

fn binding(pins map[string]winejitstream.NativePin) Binding {
	mut keys := pins.keys()
	keys.sort()
	mut hash := sha256.new()
	for key in keys { hash.write((json2.encode(key) + ':' + json2.encode(pins[key]) + '\n').bytes()) or { panic(err) } }
	mut sum := []u8{len: sha256.size}
	hash.checksum_into(mut sum)
	return Binding{entries: keys.len, digest: sum.hex()}
}

fn inputs(root string) !map[string]winejitstream.NativePin {
	mut pins := map[string]winejitstream.NativePin{}
	for path in [compiler, os.dir(compiler) + '/v.mod', os.dir(compiler) + '/snapshot.json', clang,
		os.executable(), root + '/tests/packages/wine-fork-jit-stream-inputs.v',
		root + '/tests/packages/wine-fork-jit-stream-inputs-host.v'] {
		winejitstream.native_input_add(path, mut pins)!
	}
	for path in [os.dir(compiler) + '/vlib', os.dir(compiler) + '/thirdparty',
		root + '/tools/packages/winejitstream'] {
		winejitstream.native_input_tree(path, mut pins)!
	}
	return pins
}

fn account(state string, reserve u64) !u64 {
	mut historical := u64(0)
	for name in ['wine-jit-stream-native-host-01', 'wine-jit-stream-native-host-02',
		'wine-jit-stream-native-host-03', 'wine-jit-stream-native-host-04', 'wine-jit-stream-native-host-05',
		'wine-jit-stream-native-arm-01.launch-refusal.json', 'wine-jit-stream-native-arm-01.launch-02.json'] {
		historical += winejitstream.static_state_bytes(base + '/' + name)!
	}
	if historical != old_bytes { return error('historical selected evidence changed') }
	return winejitstream.static_budget(historical, winejitstream.static_host_states_bytes(base)!, reserve)
}

fn main() { run() or { eprintln(err); exit(1) } }

fn run() ! {
	if os.args.len == 7 && os.args[1] == 'bootstrap-record' {
		// Explicit transcription from the external tool's completed observation,
		// not a claim that this executable guarded its own first compilation.
		root := os.real_path(os.args[2])
		state := os.args[3]
		if !state.starts_with(base + '/wine-jit-stream-static-inputs-host-') || os.real_path(state) != state
			|| (os.lstat(state)!).get_filetype() != .directory { return error('invalid bootstrap state') }
		log_name := os.args[4]
		if log_name !in ['bootstrap.log', 'bootstrap-02.log', 'bootstrap-03.log'] { return error('invalid fixed bootstrap log') }
		winejitstream.static_require_absent(state + '/' + log_name + '.json')!
		winejitstream.native_require_free(state, 2 * 1024 * 1024)!
		account(state, 256 * 1024)!
		mut environment := map[string]string{}
		for name in ['V', 'VEXE', 'VINIX_V_COMPILER', 'V_MACOS_V3_CALLER_VEXE',
			'V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_CALLER_VCHILD_PRESENT',
			'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'V_MACOS_V3_NO_FALLBACK',
			'V_C_ERROR_BUG_REPORT_DISABLED', 'TMPDIR', 'LC_ALL', 'LANG',
			'VFLAGS', 'VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
			'V_MACOS_V3_CHILD_VEXE_PRESENT'] {
			environment[name] = os.getenv_opt(name) or { '<unset>' }
		}
		selected := inputs(root)!
		os.write_file(state + '/' + log_name + '.json', json2.encode({
			'kind': 'Posthoc completed external tool observation; bootstrap outside its own guard, observed with 300-second stop policy.'
			'exit_code': os.args[5]
			'observed_elapsed_ms': os.args[6]
			'argv': json2.encode([compiler, '-cc', clang, '-prod', '-gc', 'none', '-manualfree',
				'-path', '@vlib|' + root + '|@vmodules', '-o', state + '/host',
				root + '/tests/packages/wine-fork-jit-stream-inputs-host.v'])
			'explicit_environment': json2.encode(environment)
			'log_sha256': winejitstream.native_input_digest(state + '/' + log_name)!
			'recorder_executable_sha256': winejitstream.native_input_digest(os.executable())!
			'compiler_sha256': winejitstream.native_input_digest(compiler)!
			'source_compiler_binding_after': json2.encode(binding(selected))
		}))!
		return
	}
	if os.args.len != 3 { return error('usage: inputs-host ROOT EXISTING_HOST_STATE') }
	root := os.real_path(os.args[1])
	state := os.args[2]
	if !state.starts_with(base + '/wine-jit-stream-static-inputs-host-') || os.real_path(state) != state
		|| (os.lstat(state)!).get_filetype() != .directory { return error('invalid fixed host state') }
	if os.read_file(@FILE)! != $embed_file('wine-fork-jit-stream-inputs-host.v').to_string()
		|| os.read_file(root + '/tools/packages/winejitstream/static_inputs.v')!
		!= $embed_file('../../tools/packages/winejitstream/static_inputs.v').to_string()
		|| os.read_file(root + '/tools/packages/winejitstream/native_guard.v')!
		!= $embed_file('../../tools/packages/winejitstream/native_guard.v').to_string() {
		return error('compiled host runner source differs')
	}
	if winejitstream.native_input_digest(compiler)! != compiler_sha { return error('selected private compiler changed') }
	os.chdir(root)!
	for name in ['guarded', 'steps.json', 'environment.json', 'host-receipt.json'] {
		winejitstream.static_require_absent(state + '/' + name)!
	}
	winejitstream.native_require_free(state, 2 * 1024 * 1024)!
	account(state, 2 * 1024 * 1024)!
	os.mkdir(state + '/guarded')!
	// A separate scratch tree permits V's temporary literal tool links. Its
	// no-follow bytes are counted before and after each guarded operation.
	winejitstream.static_require_absent(state + '/scratch')!
	os.mkdir(state + '/scratch')!
	mut environment := map[string]string{}
	for pair in ['V=' + compiler, 'VEXE=' + compiler, 'VINIX_V_COMPILER=' + compiler,
		'V_MACOS_V3_CALLER_VEXE=' + compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT=1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT=0', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT=0',
		'V_MACOS_V3_NO_FALLBACK=1', 'V_C_ERROR_BUG_REPORT_DISABLED=1',
		'TMPDIR=' + state + '/scratch', 'LC_ALL=C', 'LANG=C'] {
		at := pair.index('=') or { return error('invalid fixed environment') }
		os.setenv(pair[..at], pair[at + 1..], true)
		environment[pair[..at]] = pair[at + 1..]
	}
	for name in ['VFLAGS', 'VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'VINIX_WINE_STATIC_ASSERT_SENTINEL',
		'V_MACOS_V3_CHILD_VEXE_PRESENT'] {
		os.unsetenv(name)
		environment[name] = '<unset>'
	}
	os.write_file(state + '/environment.json', json2.encode(environment))!
	before := inputs(root)!
	os.write_file(state + '/binding-before.json', json2.encode(binding(before)))!
	limits := winejitstream.NativeLimits{timeout_ms: 60000, file_bytes: 20 * 1024 * 1024,
		total_bytes: 20 * 1024 * 1024, log_bytes: 256 * 1024, serial_bytes: 256 * 1024,
		min_free_kib: 1024 * 1024}
	mut steps := map[string]Step{}
	for name in ['inputs', 'static-test', 'static-test-prod'] {
		source := if name == 'inputs' { root + '/tests/packages/wine-fork-jit-stream-inputs.v' }
			else { root + '/tools/packages/winejitstream/static_inputs_test.v' }
		mut argv := [compiler, '-cc', clang]
		if name != 'static-test' { argv << '-prod' }
		argv << ['-gc', 'none', '-manualfree', '-path', '@vlib|' + root + '|@vmodules',
			'-o', state + '/guarded/' + name, source]
		available := winejitstream.native_require_free(state, 2 * 1024 * 1024)!
		account(state, 2 * 1024 * 1024)!
		result := winejitstream.native_guard(argv, state + '/guarded', name + '.build.log', limits)!
		steps[name + '.build'] = Step{argv: argv, free_kib: available, run: result}
		os.write_file(state + '/steps.json', json2.encode(steps))!
		account(state, 2 * 1024 * 1024)!
		if !result.stopped || result.wait_status != 0 || result.timed_out || result.size_limited || result.reason != '' {
			return error('host build failed; raw result retained: ' + name)
		}
		output := state + '/guarded/' + name
		if (os.lstat(output)!).get_filetype() != .regular { return error('host output is not ordinary') }
		steps[name + '.build'] = Step{argv: argv, free_kib: available, run: result,
			output_pin: winejitstream.native_input_digest(output)!}
		os.write_file(state + '/steps.json', json2.encode(steps))!
	}
	for name in ['static-test', 'static-test-prod', 'assertion-sentinel', 'assertion-sentinel-prod', 'plan'] {
		sentinel := name.starts_with('assertion-sentinel')
		if sentinel { os.setenv('VINIX_WINE_STATIC_ASSERT_SENTINEL', '1', true) }
		else { os.unsetenv('VINIX_WINE_STATIC_ASSERT_SENTINEL') }
		argv := if name == 'plan' { [state + '/guarded/inputs', 'plan', state] }
			else if name.ends_with('-prod') { [state + '/guarded/static-test-prod'] }
			else { [state + '/guarded/static-test'] }
		available := winejitstream.native_require_free(state, 2 * 1024 * 1024)!
		account(state, 2 * 1024 * 1024)!
		result := winejitstream.native_guard(argv, state + '/guarded', name + '.run.log', limits)!
		steps[name + '.run'] = Step{argv: argv, free_kib: available, run: result, assertion_sentinel: sentinel}
		os.write_file(state + '/steps.json', json2.encode(steps))!
		account(state, 2 * 1024 * 1024)!
		expected_status := if sentinel { 256 } else { 0 }
		if !result.stopped || result.wait_status != expected_status || result.timed_out || result.size_limited || result.reason != '' {
			return error('host check failed; raw result retained: ' + name)
		}
		if sentinel && !os.read_file(state + '/guarded/' + name + '.run.log')!.contains('wine-static intentional assertion sentinel') {
			return error('unit sentinel did not report the intentional failure')
		}
	}
	after := inputs(root)!
	os.write_file(state + '/binding-after.json', json2.encode(binding(after)))!
	if after != before { return error('selected source/compiler closure changed') }
	measured := account(state, 256 * 1024)!
	os.write_file(state + '/host-receipt.json', json2.encode({
		'argv': json2.encode(os.args)
		'explicit_environment': json2.encode(environment)
		'selected_binding': json2.encode(binding(after))
		'steps': json2.encode(steps)
		'selected_state_plus_receipt_reserve': measured.str()
		'scope': 'Host builds, unit controls and static preflight only. Full selected compiler vlib/thirdparty + source paths are hashed in sorted path order before/after; raw map not retained. No exact compiler source provenance, host SDK or transitive dynamic library closure claim. Guarded output logs/binaries monitored; separate compiler scratch counted without following links before/after. No composition or target execution.'
	}))!
	account(state, 0)!
	winejitstream.native_require_free(state, 1024 * 1024)!
	println('PASS host-only builds, controls and absent-destination preflight')
}
