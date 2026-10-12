// Compile without -prod; the deliberate failure verifies active assertions.
import crypto.sha256
import json2
import os

struct Evidence {
	architecture string
	context string
	base_commit string
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
fn git(tree string, args []string) !string {
	mut command := ['-C', tree]; command << args
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0
	return output.trim_space()
}
fn body(text string, signature string) string {
	assert text.contains(signature)
	return text.all_after(signature).all_before('\n}\n')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'receipt audit failure must be fatal'; return }
	mut control := os.new_process(os.executable()); control.set_args(['--negative-control']); control.set_redirect_stdio(); control.run()
	message := control.stdout_slurp() + control.stderr_slurp(); control.wait(); code := control.code; control.close()
	if code != 1 || !message.contains('receipt audit failure must be fatal') { panic('audit assertions must execute; compile without -prod') }
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-pipezero-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 61
	for path, hash in inputs { if !path.starts_with('kernel/') || path == 'kernel/pipe/pipe.v' { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == 'e13e66b1'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/pipe/pipe.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		read := body(generated, '__v_option_i64 pipe__Pipe__read(pipe__Pipe* this, void* _handle, void* buf, u64 _loc, u64 _count) {')
		zero := read.index('if (_count == 0)') or { panic('missing zero-count guard') }
		acquire := read.index('klock__Lock__acquire') or { panic('missing pipe lock') }
		assert zero < acquire && read.all_before('klock__Lock__acquire').contains('i64')
		assert !read.contains('memdup(') && !read.contains('malloc(') && !read.contains('array_new(')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before3-' } else { 'after-' } + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'sysnr-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else { 8 }
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init')
				assert item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				if name == 'pipezero' {
					fixture := os.read_file(state + '/pipezero/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
					assert !fixture.contains('malloc(') && !fixture.contains('array_new(')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['pipezero']
				assert text.contains('write=0 count=0 actual=-1/4 expected=0/0 alarms=1')
				assert text.contains('LINUX PIPEZERO DETAIL: kind=0 outcome=256')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX PIPEZERO: PASS')
			} else {
				assert names == ['pipezero', 'sysnr', 'access', 'open', 'runtime', 'seccompkill', 'seccomp', 'futexqueue']
				assert !text.contains('LINUX PIPEZERO FAIL') && !text.contains('LINUX PIPEZERO DETAIL')
				for kind in 0 .. 7 { assert text.contains('LINUX PIPEZERO CASE: kind=' + kind.str() + ' PASS') }
				for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
			}
			label := 'pipezero-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str()
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
		}
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['host_tests'] = digest(area + 'host-tests.log')
		artifacts['audit'] = digest(@FILE)
		record := Evidence{arch, 'Native UID1000 musl ELF64: seven groups for anonymous/named blocking/nonblocking empty, populated/full and hung-up pipes; zero reads/writes accept null, unmapped and protected buffers without waiting, changing data/readiness or SIGPIPE. Invalid, closed and wrong-access descriptors retain EBADF; eight regression cases. Directory reads and native ELF32/foreign ABI are separate', 'e13e66b1', artifacts, inputs}
		os.write_file(out + 'pipezero-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'pipezero-host-tests.log')!
	println('Native zero-length pipe reads, unchanged data/readiness and descriptor error evidence: verified')
}
