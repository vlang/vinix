// Use -nocache -cflags -O2; -prod removes assertions.
import crypto.sha256
import json2
import os

struct Evidence {
	architecture string
	context string
	artifacts map[string]string
	source_inputs map[string]string
}
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn publish(source string, output string) ! {
	bytes := os.read_bytes(source)!
	if os.exists(output) { assert os.read_bytes(output)! == bytes }
	else { os.write_file_array(output, bytes)! }
}
fn main() {
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-linux-jit-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	mut control := os.new_process(area + 'firefox-persistent/assert-check')
	control.set_redirect_stdio()
	control.run()
	message := control.stdout_slurp() + control.stderr_slurp()
	control.wait()
	assert control.code == 1 && message.contains('receipt audit failure must be fatal')
	control.close()
	inventory := json2.decode[json2.Any](os.read_file(root + 'docs/linux-syscall-coverage.json')!)!.as_map()['inputs']!.as_map_of_strings()
	assert inventory.len == 49
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'nnp-kernel-' + suffix + '/'
		for path, hash in inventory {
			assert digest(root + path) == hash
			if path.starts_with('kernel/') { assert digest(tree + path) == hash }
		}
		for phase in ['before4', 'after'] {
			state := area + 'nnp-' + phase + '-' + suffix
			receipt := json2.decode[json2.Any](os.read_file(state + '/receipt.json')!)!.as_map()
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else {
				previous := json2.decode[json2.Any](os.read_file(out + 'jit-policy-' + arch + '.json')!)!.as_map()
				assert previous['kernel_sha256']!.str() == receipt['kernel_sha256']!.str()
			}
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'after' { 4 } else { 1 }
			mut names := []string{}
			for row in rows {
				item := row.as_map()
				name := item['name']!.str()
				assert name !in names
				names << name
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init')
				assert item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				assert item['exit_code']!.int() == if phase == 'after' { 0 } else { 1 }
			}
			assert 'nnp' in names
			if phase == 'after' { assert names == ['nnp', 'seccompquery', 'seccomp', 'jit'] }
			log := os.read_file(state + '.log')!
			assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			if phase == 'before4' {
				assert log.contains('LINUX NNP FAIL: operation=39 result=0 errno=0 expected=-1/22')
				assert !log.split_into_lines().any(it.trim_space() == 'LINUX NNP: PASS')
			} else {
				assert log.contains('LINUX NNP PASS: 34 exact errors, full-width arguments and retained state')
				for name in names { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
				assert log.contains('Linux compatibility guest suite: PASS') && !log.contains('LINUX NNP FAIL')
			}
			label := 'nnp-' + (if phase == 'before4' { 'before' } else { 'after' }) + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
		}
		record := Evidence{arch,
			'Native prctl option narrowing and no_new_privs argument/state conformance; 34 exact errors; seccomp and JIT regressions; assertion-enabled audit; per-thread ownership remains unqualified',
			{'kernel': digest(tree + 'kernel/bin/vinix'), 'generated_c': digest(tree + 'kernel/obj/blob.c'),
			'build_log': digest(area + 'nnp-build-' + suffix + '.log'), 'audit': digest(@FILE),
			'compiler': digest('/Users/alex/code/v/v'), 'inventory': digest(root + 'docs/linux-syscall-coverage.json'),
			'fixture': digest(root + 'tests/linux-compat/nnpfixture/core.v'), 'controller': digest(root + 'tests/linux-compat/run.v')}, inventory}
		text := json2.encode(record, prettify: true) + '\n'
		file := out + 'nnp-' + arch + '-evidence.json'
		if os.exists(file) { assert os.read_file(file)! == text } else { os.write_file(file, text)! }
	}
	println('Native no_new_privs before/after and regression evidence: verified')
}
