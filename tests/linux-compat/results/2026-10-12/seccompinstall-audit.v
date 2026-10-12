// Compile without -prod so every assertion executes.
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
	area := '/tmp/vinix-seccomp-install-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 60
	own := 'kernel/syscall/table/container.v'
	for path, hash in inputs { if !path.starts_with('kernel/') || path == own { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == '1d4080c8'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == own
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		install := body(generated, 'multi_return_u64_u64 table__seccomp_install(u64 prog, u32 flags) {')
		assert install.contains('u64 header[2];') && !install.contains('memdup(')
		header_copy := install.index('usercopy__copy_from_user') or { panic('missing header copy') }
		length := install.index('i64 length =') or { panic('missing length validation') }
		permission := install.index('proc__no_new_privs_state') or { panic('missing permission check') }
		allocation := install.index('Array instructions = array_new(') or { panic('missing instruction allocation') }
		instruction_copy := install.last_index('usercopy__copy_from_user') or { panic('missing instruction copy') }
		verifier := install.index('proc__seccomp_check') or { panic('missing verifier') }
		attachment := install.index('proc__seccomp_attach') or { panic('missing attachment') }
		assert header_copy < length && length < permission && permission < allocation
		assert allocation < instruction_copy && instruction_copy < verifier && verifier < attachment
		assert install.count('array__free(&instructions)') == 3
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'seccompkill-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
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
				if name in ['seccompinstall', 'nnpthread'] {
					fixture := os.read_file(state + '/' + name + '/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			assert text.contains('LINUX SECCOMPINSTALL PAGE: bytes=' + if arch == 'aarch64' { '16384' } else { '4096' })
			if phase == 'before' {
				assert names == ['seccompinstall']
				assert text.contains('LINUX SECCOMPINSTALL CASE: kind=0 checks=446 PASS')
				assert text.contains('method=0 flags=0 result=-1/13 expected=14 mode=0/0 nnp=0/0')
				assert text.contains('LINUX SECCOMPINSTALL DETAIL: kind=1 outcome=256')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX SECCOMPINSTALL: PASS')
			} else {
				assert names == ['seccompinstall', 'nnpthread', 'nnp', 'seccompthread', 'seccompkill', 'seccomp', 'seccompquery', 'runtime']
				assert !text.contains('LINUX SECCOMPINSTALL FAIL') && !text.contains('LINUX SECCOMPINSTALL DETAIL')
				for kind in 0 .. 5 { assert text.contains('LINUX SECCOMPINSTALL CASE: kind=' + kind.str() + ' checks=446 PASS') }
				for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				for cycle in 0 .. 2 { for size in [32, 64, 96, 128] {
					prefix := 'LINUX SECCOMPTHREAD SLAB: cycle=' + cycle.str() + ' size=' + size.str() + ' '
					lines := text.split_into_lines().filter(it.trim_space().starts_with(prefix))
					assert lines.len >= 1 && lines.all(it.trim_space().ends_with('delta=0'))
				} }
			}
			label := 'seccompinstall-' + phase + '-' + arch
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
		record := Evidence{arch, 'Native musl ELF64: five root/CAP_SYS_ADMIN/UID1000/NNP groups, 2230 syscall/prctl checks of header/length/authorization/copy/verifier precedence, page boundaries, padding and unchanged rejection state; valid filters prove authorization. Corrected sibling/fork/exec NNP probes, eight regression cases and flat3200-filter cohorts. Notifications, foreign/ELF32 and complete sandbox isolation remain unqualified', '1d4080c8', artifacts, inputs}
		os.write_file(out + 'seccompinstall-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'seccompinstall-host-tests.log')!
	println('Native seccomp installation error precedence and task authorization evidence: verified')
}
