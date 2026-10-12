// Compile with -enable-globals -nocache -cflags -O2, without -prod.
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
	text := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0; return text.trim_space()
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
	area := '/tmp/vinix-seccomp-kill-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 60
	own := ['kernel/syscall/table/syscall_table_arm64.v', 'kernel/syscall/table/trace_amd64.v', 'kernel/userland/exit.v']
	for path, hash in inputs { if !path.starts_with('kernel/') || path in own { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == '1c2e33ce'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == own
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		fatal := body(generated, 'userland__exit_thread_with_fatal_signal(u8 v_signal) {')
		normal := body(generated, 'userland__thread_exit(i64 status, bool group) {')
		assert fatal.contains('userland__thread_exit_status(userland__encode_fatal_signal(v_signal), false)')
		assert normal.contains('userland__thread_exit_status(userland__encode_exit_status(status), group)')
		for function in [fatal, normal] { for allocation in ['memdup(', 'array_new(', 'malloc(', 'new_array'] { assert !function.contains(allocation) } }
		assert generated.contains('userland__exit_thread_with_fatal_signal((u8)(31))')
		assert generated.contains('userland__exit_thread_with_fatal_signal((u8)(9))')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' {
				if suffix == 'arm' { 'before-reviewed2-arm' } else { 'before-reviewed-x86' }
			} else { 'after-reviewed-' + suffix }
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'seccompthread-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else { 7 }
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init')
				assert item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				if name == 'seccompkill' {
					fixture := os.read_file(state + '/' + name + '/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
					assert fixture.contains('i32 __clone(') && fixture.contains('i32 tid = __clone(')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['seccompkill'] && text.contains('LINUX SECCOMPKILL FAIL: kind=0 outcome=31 signal=0')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX SECCOMPKILL: PASS')
			} else {
				assert names == ['seccompkill', 'seccompthread', 'seccomp', 'seccompquery', 'nnpthread', 'runtime', 'futexqueue']
				assert !text.contains('LINUX SECCOMPKILL FAIL') && !text.contains('LINUX SECCOMPKILL DETAIL')
				for kind in [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12] {
					wanted := if kind in [5, 6, 7] { 31 } else if kind == 8 { 9 } else { 0 }
					assert text.contains('LINUX SECCOMPKILL CASE: kind=' + kind.str() + ' signal=' + wanted.str() + ' PASS')
				}
				for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				for cycle in 0 .. 2 {
					for size in [32, 64, 96, 128] {
						prefix := 'LINUX SECCOMPTHREAD SLAB: cycle=' + cycle.str() + ' size=' + size.str() + ' '
						lines := text.split_into_lines().filter(it.trim_space().starts_with(prefix))
						assert lines.len >= 1 && lines.all(it.trim_space().ends_with('delta=0'))
					}
				}
			}
			label := 'seccompkill-' + phase + '-' + arch
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
		record := Evidence{arch, 'Native musl ELF64 UID1000 raw-clone tasks: KILL_THREAD (including data bits) and strict SIGKILL leave siblings alive; KILL_PROCESS/unknown actions kill the group; last-task signals are preserved; strict read/write/exit and actual signal return, strict-peer TSYNC refusal and CHILD_CLEARTID/TID cleanup; seven regression cases and flat3200-filter storage cohorts. Core dumps and foreign/ELF32 paths remain unqualified', '1c2e33ce', artifacts, inputs}
		os.write_file(out + 'seccompkill-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'seccompkill-host-tests.log')!
	println('Native seccomp task/group termination and strict whitelist evidence: verified')
}
