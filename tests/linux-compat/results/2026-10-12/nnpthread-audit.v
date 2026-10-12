// Use -nocache -cflags -O2. The deliberate assertion also guards against -prod.
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
fn publish(source string, output string) ! {
	bytes := os.read_bytes(source)!
	if os.exists(output) { assert os.read_bytes(output)! == bytes }
	else { os.write_file_array(output, bytes)! }
}
fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}
fn git(tree string, args []string) !string {
	mut process := os.new_process('git')
	mut command := ['-C', tree]
	command << args
	process.set_args(command)
	process.set_redirect_stdio()
	process.run()
	result := process.stdout_slurp() + process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	assert code == 0
	return result.trim_space()
}
fn main() {
	if '--negative-control' in os.args {
		assert false, 'receipt audit failure must be fatal'
		return
	}
	mut control := os.new_process(os.executable())
	control.set_args(['--negative-control'])
	control.set_redirect_stdio()
	control.run()
	message := control.stdout_slurp() + control.stderr_slurp()
	control.wait()
	code := control.code
	control.close()
	if code != 1 || !message.contains('receipt audit failure must be fatal') {
		panic('audit assertions must execute; compile without -prod')
	}
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-nnp-thread-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inventory := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inventory.len == 53
	assert os.read_file(area + 'host-tests2.log')!.contains('8 passed, 8 total')
	for path, hash in inventory { assert digest(root + path) == hash }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == 'fafff0b8'
		mut changed := git(tree, ['diff', '--name-only', 'HEAD'])!.split_into_lines()
		changed.sort()
		assert changed == ['kernel/fs/procfs.v', 'kernel/proc/container.v', 'kernel/proc/proc.v',
			'kernel/proc/proc_amd64.v', 'kernel/proc/proc_arm64.v', 'kernel/proc/thread_attach.v',
			'kernel/sched/sched_amd64.v', 'kernel/sched/sched_arm64.v',
			'kernel/syscall/table/container.v', 'kernel/syscall/table/linux_common.v']
		for path, hash in inventory {
			if path.starts_with('kernel/') { assert digest(tree + path) == hash }
		}
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		status_body := generated.all_after('string proc__process_status_text(i64 pid, i64 tid, proc__Namespace* viewer) {').all_before('\n}\n')
		assert status_body.count('(void*)(target->process) != (void*)(process)') == 2
		assert !status_body.contains('array_eq') && !status_body.contains('__ptr_eq')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before-test5-' + suffix } else { 'final2-' + suffix }
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			kernel := receipt['kernel_sha256']!.str()
			assert kernel == digest(state + '/kernel/bin/vinix')
			assert kernel == digest(if phase == 'before' { area + 'before-' + suffix + '/bin/vinix' } else { tree + 'kernel/bin/vinix' })
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else { 6 }
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
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			log := os.read_file(state + '.log')!
			assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['nnpthread']
				assert log.contains('LINUX NNPTHREAD FAIL: direct=0') && log.contains('outcome=5888')
				assert !log.split_into_lines().any(it.trim_space() == 'LINUX NNPTHREAD: PASS')
			} else {
				assert names == ['nnpthread', 'nnp', 'seccompquery', 'seccomp', 'jit', 'runtime']
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				assert log.contains('Linux compatibility guest suite: PASS') && !log.contains('LINUX NNPTHREAD FAIL')
				assert log.count('LINUX NNPTHREAD CHILD: fork/exec retained 0') == 2
				assert log.count('LINUX NNPTHREAD CHILD: fork/exec retained 1') == 3
			}
			label := 'nnpthread-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
			artifacts[phase + '_kernel'] = kernel
		}
		cap := area + 'final2-cap-' + suffix
		assert artifacts['before_kernel'] != artifacts['after_kernel']
		receipt := object(cap + '/inputs.json')!
		assert receipt['suite']!.str() == 'capability-exec'
		assert receipt['arch']!.str() == if arch == 'aarch64' { 'aarch64' } else { 'amd64' }
		assert receipt['native_guest_returncode']!.int() == 0
		assert receipt['selected_kernel_sha256']!.str() == artifacts['after_kernel']
		assert digest(cap + '/kernel/bin/vinix') == artifacts['after_kernel']
		assert receipt['iso_sha256']!.str() == digest(cap + '/test.iso')
		assert receipt['fixture_elf_sha256']!.str() == digest(cap + '/init')
		assert receipt['source_sha256']!.as_map()['guest.c']!.str() == digest(root + 'tests/capability-exec/guest.c')
		log := os.read_file(cap + '.log')!
		assert log.contains('CAP EXEC GUEST: PASS') && !log.contains('CAP EXEC FAIL')
		assert log.count('CAP EXEC PASS:') == 7 && !log.contains('KERNEL PANIC')
		publish(cap + '/inputs.json', out + 'nnpthread-cap-' + arch + '.json')!
		publish(cap + '.log', out + 'nnpthread-cap-' + arch + '.log')!
		artifacts['capability_receipt'] = digest(cap + '/inputs.json')
		artifacts['capability_log'] = digest(cap + '.log')
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['kernel_v_compiler'] = digest(area + 'v')
		artifacts['build_log'] = digest(area + 'after-build4-' + suffix + '.log')
		artifacts['audit'] = digest(@FILE)
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['host_tests'] = digest(area + 'host-tests2.log')
		record := Evidence{arch,
			'Native musl ELF64: task-local no_new_privs, independent siblings, clone/fork/exec and nonleader exec, caller-based seccomp authorization, live/zombie procfs status; six compatibility and six capability-exec groups; no new allocations or frees; seccomp ownership/TSYNC and complete sandbox isolation remain unqualified',
			'fafff0b8', artifacts, inventory}
		encoded := json2.encode(record, prettify: true) + '\n'
		path := out + 'nnpthread-' + arch + '-evidence.json'
		if os.exists(path) { assert os.read_file(path)! == encoded } else { os.write_file(path, encoded)! }
	}
	publish(area + 'host-tests2.log', out + 'nnpthread-host-tests.log')!
	println('Native task-local no_new_privs and regression evidence: verified')
}
