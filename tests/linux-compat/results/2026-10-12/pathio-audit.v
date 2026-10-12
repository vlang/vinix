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
fn definition(text string, name string) string {
	signatures := text.split_into_lines().filter(it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert signatures.len == 1
	return body(text, signatures[0])
}
fn main() {
	if '--negative-control' in os.args { assert false, 'receipt audit failure must be fatal'; return }
	mut control := os.new_process(os.executable()); control.set_args(['--negative-control']); control.set_redirect_stdio(); control.run()
	message := control.stdout_slurp() + control.stderr_slurp(); control.wait(); code := control.code; control.close()
	if code != 1 || !message.contains('receipt audit failure must be fatal') { panic('audit assertions must execute; compile without -prod') }
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-pathio-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 62
	for path, hash in inputs { if !path.starts_with('kernel/') || path in ['kernel/file/file.v', 'kernel/syscall/table/linux_common.v'] { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == '4f30c294453fc52efd13745d8d04b84ed3d72fa7'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/file/file.v\nkernel/syscall/table/linux_common.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		positioned := definition(generated, 'file__pread')
		position_guard := positioned.index('resource__o_path') or { panic('missing positioned O_PATH guard') }
		policy := positioned.index('file__Handle__mac_check') or { panic('missing positioned MAC check') }
		assert position_guard < policy
		write := definition(generated, 'file__syscall_pwrite')
		write_guard := write.index('resource__o_path') or { panic('missing positioned write O_PATH guard') }
		write_policy := write.index('file__Handle__mac_check') or { panic('missing positioned write MAC check') }
		assert write_guard < write_policy
		access := definition(generated, 'table__linux_iov_access_error')
		snapshot := access.index('i64 flags = fd->handle->flags;') or { panic('missing scalar snapshot') }
		release := access.index('file__FD__unref(fd);') or { panic('missing FD release') }
		use := access.index('flags & resource__o_accmode;') or { panic('missing access bits') }
		assert snapshot < release && release < use
		assert access.count('file__FD__unref(fd);') == 1
		assert !access.all_after('file__FD__unref(fd);').contains('fd->')
		assert access.contains('resource__o_path') && access.contains('resource__o_rdwr')
		assert !access.contains('memdup(') && !access.contains('malloc(') && !access.contains('array_new(')
		for name in ['table__syscall_linux_readv', 'table__syscall_linux_writev'] {
			vector := definition(generated, name)
			permission := vector.index('table__linux_iov_access_error') or { panic('missing vector access check') }
			validation := vector.index('table__validate_linux_iov') or { panic('missing vector validation') }
			assert permission < validation
		}
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before2-' } else { 'after-final-' } + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'readerror-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
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
				if name == 'pathio' {
					fixture := os.read_file(state + '/pathio/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
					assert !fixture.contains('malloc(') && !fixture.contains('array_new(')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['pathio']
				assert text.contains('count=0 actual=0/0 expected=-1/9')
				assert text.contains('LINUX PATHIO DETAIL: ordinary=1 outcome=256')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX PATHIO: PASS')
			} else {
				assert names == ['pathio', 'readerror', 'pipezero', 'open', 'sharedmem', 'runtime', 'seccomp', 'futexqueue']
				assert !text.contains('LINUX PATHIO FAIL') && !text.contains('LINUX PATHIO DETAIL')
				for ordinary in 0 .. 2 { assert text.contains('LINUX PATHIO CASE: ordinary=' + ordinary.str() + ' checks=240 PASS') }
				for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
			}
			label := 'pathio-' + phase + '-' + arch
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
		record := Evidence{arch, 'Native musl ELF64 root/UID1000: 480 checks of O_PATH scalar/positioned/vector refusal on files/directories/FIFOs/symlinks and duplicates; empty vectors and malformed pointers require EBADF before import; metadata and valid multi-iovec I/O remain usable. UID1000 retains EACCES on the ordinary open of a root-owned mode-0600 file. Unchanged controls falsely return zero for empty O_PATH readv. Eight regression cases. Extended vector descriptor identity across concurrent close/reuse and foreign ABI remain unqualified', '4f30c2944', artifacts, inputs}
		os.write_file(out + 'pathio-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'pathio-host-tests.log')!
	println('Native O_PATH byte refusal, vector access precedence and borrowed-reference evidence: verified')
}
