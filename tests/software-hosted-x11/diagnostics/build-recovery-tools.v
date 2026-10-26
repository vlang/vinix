module main

import os
import json2
import crypto.sha256
import strconv

const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const source_dir = '/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree/tests/software-hosted-x11/diagnostics'
const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'

fn sha(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut h := sha256.new()
	defer { unsafe { h.free() } }
	mut buf := []u8{len: 1024 * 1024}
	defer { unsafe { buf.free() } }
	for {
		n := f.read(mut buf) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		h.write(buf[..n])!
	}
	return h.sum([]u8{}).hex()
}

fn actual_df() !(u64, string) {
	mut p := os.new_process('/bin/df')
	defer { p.close() }
	p.set_args(['-k', state]); p.set_redirect_stdio_merged(); p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	text := p.stdout_slurp(); p.wait()
	lines := text.trim_space().split_into_lines()
	if p.code != 0 || lines.len != 2 || !lines[0].contains('1024-blocks') { return error('actual df format differs') }
	fields := lines[1].fields()
	if fields.len != 9 || fields[0] != '/dev/disk3s5' || fields[8] != '/System/Volumes/Data' { return error('actual df volume differs') }
	kib := strconv.parse_uint(fields[3], 10, 64)!
	return kib, text
}

fn run() ! {
	if os.args.len != 3 || os.args[1] !in ['archive-native02', 'archive-arm03', 'supervise-recovery', 'recovery-guard-check'] {
		return error('expected fixed tool name and independently reviewed source SHA256')
	}
	stem := os.args[1]
	source := source_dir + '/' + stem + '.v'
	output := state + '/' + stem + '-01'
	receipt := state + '/' + stem + '-build-01.json'
	for path in [output, receipt, output + '.build-log', output + '.build-argv.json', output + '.build-exit.json'] {
		if os.exists(path) || os.is_link(path) { return error('build requires new outputs: ' + path) }
	}
	if sha(source)! != os.args[2] { return error('reviewed source differs') }
	if sha(compiler)! != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5' { return error('compiler differs') }
	before_kib, before := actual_df()!
	if before_kib < u64(550) * 1024 { return error('actual df below550MiB build gate') }
	mut pins := map[string]string{}
	for path in [compiler, source, source_dir + '/recoveryguard/recoveryguard.v', @FILE, os.executable()] { pins[path] = sha(path)! }
	argv := [compiler, '-prod', '-path', '@vlib|' + source_dir + '|@vmodules', '-o', output, source]
	os.write_file(output + '.build-argv.json', json2.encode(argv))!
	mut p := os.new_process(argv[0])
	defer { p.close() }
	p.set_args(argv[1..]); p.set_redirect_stdio_merged(); p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	text := p.stdout_slurp(); p.wait()
	os.write_file(output + '.build-log', text)!
	os.write_file(output + '.build-exit.json', json2.encode({'exit_code': p.code}))!
	if p.code != 0 { return error('build failed; retained compiler log: ' + output + '.build-log') }
	for path, wanted in pins { if sha(path)! != wanted { return error('build input changed: ' + path) } }
	for path in [output, output + '.build-argv.json', output + '.build-log', output + '.build-exit.json'] { pins[path] = sha(path)! }
	after_kib, after := actual_df()!
	os.write_file(receipt, json2.encode({
		'pins': json2.encode(pins), 'driver_argv': json2.encode(os.args),
		'actual_df_before': before, 'actual_df_after': after,
		'available_kib_before': before_kib.str(), 'available_kib_after': after_kib.str(),
		'scope': 'Tiny host -prod default-collector build only. No ASan, allocation tracking, manualfree, archive, removal, VM or target-behavior acceptance.'
	}))!
	println('PASS ' + stem + ' binary=' + pins[output] + ' build=' + sha(receipt)! + ' actual_available_kib=' + after_kib.str())
}

fn main() { run() or { eprintln(err); exit(1) } }
