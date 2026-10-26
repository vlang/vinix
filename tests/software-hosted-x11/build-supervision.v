module main

// Every build attempt and scratch path stays in the same40MiB external scope.
import crypto.sha256
import json2
import nativeguard
import os
import time

#include <sys/stat.h>

const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const output_root = state + '/native-supervision-host-01'
const suite = '/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree/tests/software-hosted-x11'
const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'

fn sha(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn allocation(path string) !u64 {
	mut stat := C.stat{}
	if unsafe { C.lstat(&char(path.str), &stat) } != 0 || stat.st_blocks < 0 { return error('build allocation lstat failed') }
	mut total := u64(stat.st_blocks) * 512
	if stat.st_mode & C.S_IFMT == C.S_IFDIR { for name in os.ls(path)! { total += allocation(path + '/' + name)! } }
	return total
}

fn df() !(u64, string) {
	path := output_root + '/driver-df-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	observation := nativeguard.actual_df(state, path)!
	return observation.available / 1024, observation.text
}

fn monitored(argv []string, output string, wall_ms int) !int {
	monitor := output + '.monitor'
	if os.exists(monitor) || os.is_link(monitor) { return error('monitor scope already exists') }
	os.mkdir(monitor)!
	result := nativeguard.supervise(argv, os.getwd(), state, [output_root], output + '.log', monitor + '/df',
		nativeguard.Limits{start_bytes: u64(550) << 20, floor_bytes: u64(550) << 20,
			cap_bytes: (u64(40) << 20) - 65536, wall_ms: wall_ms, sample_ms: 1000})!
	os.write_file(monitor + '/result.json', json2.encode(result))!
	if result.reason != '' { return error('small host run refused: ' + result.reason) }
	return result.cleanup.exit_code
}

fn run() ! {
	nativeguard.watch_interrupts()!
	if os.args.len == 5 && os.args[1] == '--check' {
		for name in os.args[2..] { if name.len == 0 || !name.bytes().all((it >= `0` && it <= `9`) || it == `-` || (it >= `a` && it <= `z`)) { return error('invalid fixed control basename') } }
		if !os.args[2].starts_with('supervision-check-') || !os.args[3].starts_with('supervise-') { return error('requires compiled fixed control and supervisor names') }
		available, before := df()!
		if available < u64(550) * 1024 || allocation(output_root)! > u64(36) << 20 { return error('controls require550MiB free and4MiB namespace headroom') }
		output := output_root + '/controls-' + os.args[4]
		for suffix in ['', '.argv.json', '.log', '.exit.json', '.run.json'] { if os.exists(output + suffix) || os.is_link(output + suffix) { return error('control output already exists') } }
		executable := output_root + '/' + os.args[2]
		supervisor := output_root + '/' + os.args[3]
		mut pins := map[string]string{}
		for path in [@FILE, os.executable(), executable, supervisor, suite + '/nativeguard/guard.v', suite + '/supervision-check.v', suite + '/supervise.v', suite + '/diagnostics/recoveryguard/recoveryguard.v'] { pins[path] = sha(path)! }
		argv := [executable, '--out=' + output, '--supervisor=' + supervisor]
		os.write_file(output + '.argv.json', json2.encode(argv))!
		code := monitored(argv, output, 120000)!
		os.write_file(output + '.exit.json', json2.encode({'exit_code': code}))!
		after_kib, after := df()!
		bytes := allocation(output_root)!
		for path, wanted in pins { if sha(path)! != wanted { return error('control source/tool changed') } }
		for suffix in ['.argv.json', '.log', '.exit.json'] { pins[output + suffix] = sha(output + suffix)! }
		if os.exists(output + '/results.json') { pins[output + '/results.json'] = sha(output + '/results.json')! }
		os.write_file(output + '.run.json', json2.encode({'pins': json2.encode(pins), 'exit_code': code.str(), 'actual_df_before': before,
			'actual_df_after': after, 'namespace_allocated_bytes_before_final_receipt': bytes.str(), 'scope': 'Host control execution; sampled550MiB floor/40MiB total external namespace cap with64KiB final-receipt reserve; no target/image/VM/native.'}))!
		final_bytes := allocation(output_root)!
		if code != 0 || final_bytes > u64(40) << 20 || after_kib < u64(550) * 1024 { return error('controls failed or storage gate exceeded; all attempts retained') }
		println('PASS controls=' + output + ' receipt=' + sha(output + '.run.json')! + ' namespace_bytes=' + final_bytes.str())
		return
	}
	if os.args.len == 2 && os.args[1] == '--inspect' {
		mut hashes := map[string]string{}
		os.setenv('PATH', '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
		for name in ['df', 'cp', 'tar', 'ld.lld', 'xorriso', 'mformat', 'mmd', 'mcopy'] {
			path := os.find_abs_path_of_executable(name)!
			hashes[path] = sha(path)!
		}
		for name in ['supervise', 'supervision-check', 'build-supervision'] { hashes[suite + '/' + name + '.v'] = sha(suite + '/' + name + '.v')! }
		for path in [suite + '/nativeguard/guard.v', compiler, os.executable(), output_root + '/bootstrap-source.v', output_root + '/bootstrap.log', output_root + '/build-supervision', output_root + '/bootstrap-' + os.file_name(os.executable()).all_after_last('-') + '.log'] { hashes[path] = sha(path)! }
		_, actual := df()!
		os.write_file(output_root + '/inspection.json', json2.encode({'hashes': json2.encode(hashes), 'actual_df': actual, 'namespace_bytes': allocation(output_root)!.str(),
			'bootstrap_argv': json2.encode([compiler, '-enable-globals', '-nocache', '-path', '@vlib|' + suite + '|' + suite + '/diagnostics|@vmodules', '-o', os.executable(), 'tests/software-hosted-x11/build-supervision.v']),
			'bootstrap_cwd': os.dir(os.dir(suite)),
			'bootstrap_tmpdir': output_root + '/scratch', 'scope': 'Small host bootstrap/profile inventory only; no VM/staging/target/native.'}))!
		println(json2.encode(hashes))
		return
	}
	if os.args.len != 4 || os.args[1] !in ['supervise', 'supervision-check'] || os.args[2].len != 64 ||
		os.args[3].len == 0 || !os.args[3].bytes().all(it >= `0` && it <= `9`) { return error('use TOOL REVIEWED_SOURCE_SHA ATTEMPT_NUMBER') }
	stem := os.args[1]
	source := suite + '/' + stem + '.v'
	if sha(source)! != os.args[2] || sha(compiler)! != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5' { return error('reviewed source/compiler differs') }
	available, before := df()!
	if available < u64(550) * 1024 || allocation(output_root)! > u64(36) << 20 { return error('build requires550MiB free and4MiB namespace headroom') }
	output := output_root + '/' + stem + '-' + os.args[3]
	for suffix in ['', '.argv.json', '.log', '.exit.json', '.build.json'] { if os.exists(output + suffix) || os.is_link(output + suffix) { return error('build output already exists') } }
	mut pins := map[string]string{}
	for path in [source, compiler, @FILE, os.executable(), suite + '/nativeguard/guard.v', suite + '/diagnostics/recoveryguard/recoveryguard.v'] { pins[path] = sha(path)! }
	argv := [compiler, '-prod', '-enable-globals', '-nocache', '-path', '@vlib|' + suite + '|' + suite + '/diagnostics|@vmodules', '-o', output, source]
	os.setenv('TMPDIR', output_root + '/scratch', true)
	os.write_file(output + '.argv.json', json2.encode(argv))!
	code := monitored(argv, output, 120000)!
	os.write_file(output + '.exit.json', json2.encode({'exit_code': code}))!
	after_kib, after := df()!
	bytes := allocation(output_root)!
	for path, wanted in pins { if sha(path)! != wanted { return error('build source/tool changed') } }
	for suffix in ['.argv.json', '.log', '.exit.json'] { pins[output + suffix] = sha(output + suffix)! }
	if os.exists(output) { pins[output] = sha(output)! }
	os.write_file(output + '.build.json', json2.encode({'pins': json2.encode(pins), 'exit_code': code.str(), 'actual_df_before': before,
		'actual_df_after': after, 'namespace_allocated_bytes_before_final_receipt': bytes.str(), 'scratch': output_root + '/scratch',
		'scope': 'Host -prod default collector compile, sampled550MiB floor/40MiB cap with64KiB final-receipt reserve. No ASan/tracking/manualfree, target build, image or VM.'}))!
	final_bytes := allocation(output_root)!
	if code != 0 || final_bytes > u64(40) << 20 || after_kib < u64(550) * 1024 { return error('build failed or storage gate exceeded; attempts retained') }
	println('PASS build=' + output + ' sha=' + sha(output)! + ' receipt=' + sha(output + '.build.json')! + ' namespace_bytes=' + final_bytes.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
