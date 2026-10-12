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
	area := '/tmp/vinix-readerror-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 61
	for path, hash in inputs { if !path.starts_with('kernel/') || path == 'kernel/file/file.v' { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == '08316b06'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/file/file.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		read := body(generated, '__v_option_i64 file__Handle__read(file__Handle* this, void* buf, u64 count) {')
		assert read.contains('errno__set(errno__eisdir);')
		policy := read.index('file__Handle__mac_check') or { panic('missing MAC check') }
		type_check := read.index('if (stat__isdir(') or { panic('missing directory type check') }
		stream := read.index('file__stream_mode') or { panic('missing stream path') }
		assert policy < type_check && type_check < stream
		assert !read.contains('memdup(') && !read.contains('malloc(') && !read.contains('array_new(')
		user_read := body(generated, '__v_option_i64 file__Handle__read_to_user(file__Handle* this, u64 address, u64 count) {')
		assert user_read.contains('return file__Handle__read(this, (void*)(NULL), 0);')
		range_check := user_read.index('usercopy__user_range') or { panic('missing range check') }
		guard := user_read.index('if (stat__isdir(mode))') or { panic('missing user directory type check') }
		writable := user_read.index('usercopy__writable') or { panic('missing destination probe') }
		reservation := user_read.index('proc__reserve_kernel') or { panic('missing scratch reservation') }
		assert range_check < guard && guard < writable && writable < reservation
		prefix := user_read.all_before('usercopy__writable')
		assert prefix.contains('errno__set(errno__eisdir);') && prefix.contains('file__Handle__mac_check')
		assert !prefix.contains('memdup(') && !prefix.contains('malloc(') && !prefix.contains('array_new(')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before2-' } else { 'after-' } + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'pipezero-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
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
				if name == 'readerror' {
					fixture := os.read_file(state + '/readerror/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
					assert !fixture.contains('malloc(') && !fixture.contains('array_new(')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['readerror']
				assert text.contains('count=0 actual=0/0 expected=-1/21')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX READERROR: PASS')
			} else {
				assert names == ['readerror', 'pipezero', 'sysnr', 'access', 'open', 'runtime', 'seccomp', 'futexqueue']
				assert !text.contains('LINUX READERROR FAIL') && !text.contains('LINUX READERROR DETAIL')
				for ordinary in 0 .. 2 { assert text.contains('LINUX READERROR CASE: ordinary=' + ordinary.str() + ' checks=64 PASS') }
				for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
			}
			label := 'readerror-' + phase + '-' + arch
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
		record := Evidence{arch, 'Native musl ELF64 root/UID1000: 128 checks of directory EISDIR for zero/one/4096 bytes on root/tmpfs/procfs/sysfs, unreadable/protected buffers, invalid-range EFAULT and descriptor EBADF, unchanged directory offsets and regular zero/data/EOF reads; eight regression cases. Vectored, O_PATH and foreign ABI read errors remain separate', '08316b06', artifacts, inputs}
		os.write_file(out + 'readerror-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'readerror-host-tests.log')!
	println('Native directory read errors, validation order and retained file semantics: verified')
}
