// Compile without -prod. Incomplete reports must fail the qualification audit.
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
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) { assert os.read_bytes(output)! == data }
	else { os.write_file_array(output, data)! }
}
fn check_rows(path string) ! {
	rows := json2.decode[json2.Any](os.read_file(path)!)!.as_array()
	ops := rows.filter(it.as_map()['report']!.str() == 'PERF-OPS')
	churn := rows.filter(it.as_map()['report']!.str() == 'PERF-CHURN')
	cache := rows.filter(it.as_map()['report']!.str() == 'PERF-CACHE')
	assert ops.len == 36 && churn.len == 4 && cache.len == 1, 'complete retention rows required'
	for row in ops { assert row.as_map()['count']!.str() == '200' && row.as_map()['bytes_per_op']!.str() == '0' }
	for row in churn { assert row.as_map()['runs']!.str() == '300' && row.as_map()['per_run_bytes']!.str() == '0' }
	assert cache[0].as_map()['written_mb']!.str() == '32'
}
fn control(args []string, expected string) {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(expected) { panic('negative audit control did not execute') }
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-timeout' in os.args { check_rows(os.args[2])!; return }
	control(['--negative-control'], 'audit assertions must execute')
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-pipezero-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	control(['--negative-timeout', area + 'perf-retention.json'], 'complete retention rows required')
	check_rows(area + 'perf-retention-final.json')!
	assert os.read_file(area + 'perf-retention.log')!.contains('ERROR: overall measurement timeout expired')
	assert !os.read_file(area + 'perf-retention-final.log')!.contains('ERROR: ')
	original := object(out + 'pipezero-aarch64-evidence.json')!
	inputs := original['source_inputs']!.as_map_of_strings()
	assert inputs.len == 61
	for path, hash in inputs { assert digest(area + 'kernel-arm/' + path) == hash }
	mut artifacts := map[string]string{}
	for label in ['timeout', 'qualified'] {
		input := if label == 'timeout' { 'perf-retention' } else { 'perf-retention-final' }
		for extension in ['json', 'log'] {
			file := area + input + '.' + extension
			publish(file, out + 'pipezero-storage-' + label + '-aarch64.' + extension)!
			artifacts[label + '_' + extension] = digest(file)
		}
	}
	artifacts['kernel'] = digest(area + 'kernel-arm/kernel/bin/vinix')
	assert artifacts['kernel'] == original['artifacts']!.as_map_of_strings()['after_kernel']
	artifacts['kernel_generated_c'] = digest(area + 'kernel-arm/kernel/obj/blob.c')
	assert artifacts['kernel_generated_c'] == original['artifacts']!.as_map_of_strings()['kernel_generated_c']
	artifacts['desktop'] = digest('/tmp/vinix-seccomp-alloc-1012/desktop')
	assert artifacts['desktop'] == object('/tmp/vinix-seccomp-alloc-1012/desktop-input.json')!['sha256']!.str()
	artifacts['performance_controller'] = digest('/tmp/vinix-seccomp-1012/perf')
	artifacts['audit'] = digest(@FILE)
	record := Evidence{'aarch64', 'Native QEMU/HVF, isolated e13e66b1 kernel plus zero-count pipe guard, frozen desktop input used only for harness staging: complete one-round ops/churn/cache under2400s,36x200 syscall operations retain0 bytes/op,4x300 program executions retain0 bytes/run,32MiB cache workload. Initial two-round600s report timed out after21 rows and is explicitly rejected as complete evidence. Desktop readiness is not qualified by these non-desktop scenarios', artifacts, inputs}
	os.write_file(out + 'pipezero-storage-aarch64-evidence.json', json2.encode(record, prettify: true) + '\n')!
	println('Native pipe-kernel storage workload and rejected timeout evidence: verified')
}
