module main

// Fixed second compilation preserves the first parser-refusal outputs in place.
import os
import json2
import crypto.sha256
import strconv

const state = '/Users/alex/.cache/vinix-package-hosted-launch-options-guest-20261026-a'
const source_dir = '/Users/alex/code/vinix/build/package-hosted-launch-options-guest-worktree/tests/software-hosted-x11/diagnostics'
const compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'

fn sha(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn run() ! {
	if os.args.len != 2 { return error('expected independently reviewed supervisor source SHA256') }
	source := source_dir + '/supervise-recovery.v'
	output := state + '/supervise-recovery-02'
	for suffix in ['', '.build.json', '.argv.json', '.log', '.exit.json'] {
		if os.exists(output + suffix) || os.is_link(output + suffix) { return error('retry requires new outputs') }
	}
	if sha(source)! != os.args[1] || sha(compiler)! != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5' { return error('reviewed source/compiler differs') }
	mut df := os.new_process('/bin/df')
	defer { df.close() }
	df.set_args(['-k', state]); df.set_redirect_stdio_merged(); df.run()
	C.close(df.stdio_fd[0]); df.stdio_fd[0] = -1
	before := df.stdout_slurp(); df.wait()
	lines := before.trim_space().split_into_lines()
	if df.code != 0 || lines.len != 2 || !lines[0].contains('1024-blocks') { return error('actual df format differs') }
	fields := lines[1].fields()
	if fields.len != 9 || fields[0] != '/dev/disk3s5' || fields[8] != '/System/Volumes/Data' || strconv.parse_uint(fields[3], 10, 64)! < u64(550) * 1024 { return error('actual df below550MiB or volume differs') }
	mut pins := map[string]string{}
	for path in [source, compiler, source_dir + '/recoveryguard/recoveryguard.v', @FILE, os.executable()] { pins[path] = sha(path)! }
	argv := [compiler, '-prod', '-path', '@vlib|' + source_dir + '|@vmodules', '-o', output, source]
	os.write_file(output + '.argv.json', json2.encode(argv))!
	mut p := os.new_process(compiler)
	defer { p.close() }
	p.set_args(argv[1..]); p.set_redirect_stdio_merged(); p.run()
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	text := p.stdout_slurp(); p.wait()
	os.write_file(output + '.log', text)!
	os.write_file(output + '.exit.json', json2.encode({'exit_code': p.code}))!
	if p.code != 0 { return error('retry build failed; log retained') }
	for path, wanted in pins { if sha(path)! != wanted { return error('build input changed') } }
	for path in [output, output + '.argv.json', output + '.log', output + '.exit.json', state + '/supervise-recovery-01.build-log', state + '/supervise-recovery-01.build-argv.json', state + '/supervise-recovery-01.build-exit.json'] { pins[path] = sha(path)! }
	os.write_file(output + '.build.json', json2.encode({'pins': json2.encode(pins), 'actual_df_before': before,
		'scope': 'Host -prod default-collector retry build only. Failed first parser logs retained. No ASan, allocation tracking, manualfree, archive, removal, VM or native acceptance.'}))!
	println('PASS supervisor retry binary=' + pins[output] + ' build=' + sha(output + '.build.json')!)
}

fn main() { run() or { eprintln(err); exit(1) } }
