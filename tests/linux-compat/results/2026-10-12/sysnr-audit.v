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
	area := '/tmp/vinix-sysnr-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 60
	own := ['kernel/syscall/table/syscall_table_arm64.v', 'kernel/syscall/table/trace_amd64.v',
		'kernel/userland/userland.v', 'kernel/userland/userland_arm64.v']
	for path, hash in inputs { if !path.starts_with('kernel/') || path in own { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == 'ee6a8aae'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == own.join('\n')
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		trace := body(generated, if arch == 'aarch64' { 'u64 table__syscall_trace(void* gpr_state) {' } else { 'u64 table__syscall_trace(local__GPRState* frame) {' })
		assert trace.contains('u64 nr = (u64)((u32)(' + if arch == 'aarch64' { 'gpr->x8));' } else { 'frame->rax));' })
		assert trace.contains('->syscall_nr = (i64)((i32)(nr));')
		assert trace.contains('(slot == table__seccomp_verdict_nr) || (slot != nr)')
		assert trace.contains('if (nr == table__seccomp_verdict_nr)')
		assert trace.contains(if arch == 'aarch64' { 'return (u64)(table__linux_syscall_max);' } else { 'return (u64)(512);' })
		entry := body(generated, 'u64 table__seccomp_entry(proc__Thread* t, local__GPRState* ' + if arch == 'aarch64' { 'gpr, u64 nr) {' } else { 'frame, u64 nr) {' })
		assert entry.contains('if (nr == table__seccomp_verdict_nr)')
		assert entry.contains(if arch == 'aarch64' { 't->seccomp_return = gpr->x0;' } else { 't->seccomp_return = frame->rax;' })
		restart := body(generated, 'void userland__prepare_syscall_restart(local__GPRState* context) {')
		assert restart.contains(if arch == 'aarch64' { 'i32 nr = (i32)(ctx->x8);' } else { 'i32 nr = (i32)(t->restart_nr);' })
		assert restart.contains(if arch == 'aarch64' { 'ctx->x0 = t->syscall_x0;' } else { 'ctx->rax = t->restart_nr;' })
		if arch == 'x86_64' { assert trace.contains('t->restart_nr = frame->rax;') }
		for changed in [trace, entry, restart] {
			assert !changed.contains('memdup(') && !changed.contains('malloc(') && !changed.contains('array_new(')
		}
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before3-' } else { 'after-' } + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'seccompalloc-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['kernel'] }
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
				if name == 'sysnr' {
					fixture := os.read_file(state + '/sysnr/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
					assert !fixture.contains('malloc(') && !fixture.contains('array_new(')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['sysnr']
				assert text.contains('nr=1ff actual=0/0 expected=-1/38')
				assert text.contains('LINUX SYSNR DETAIL: kind=0 outcome=256')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX SYSNR: PASS')
			} else {
				assert names == ['sysnr', 'seccomp', 'seccompquery', 'seccompkill', 'seccompthread', 'nnpthread', 'runtime', 'futexqueue']
				assert !text.contains('LINUX SYSNR FAIL') && !text.contains('LINUX SYSNR DETAIL')
				for kind in 0 .. 7 { assert text.contains('LINUX SYSNR CASE: kind=' + kind.str() + ' PASS') }
				for name in names { assert text.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				for cycle in 0 .. 2 { for size in [32, 64, 96, 128] {
					prefix := 'LINUX SECCOMPTHREAD SLAB: cycle=' + cycle.str() + ' size=' + size.str() + ' '
					lines := text.split_into_lines().filter(it.trim_space().starts_with(prefix))
					assert lines.len >= 1 && lines.all(it.trim_space().ends_with('delta=0'))
				} }
			}
			label := 'sysnr-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str()
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
		}
		jobs := area + 'jobs-' + suffix
		job_inputs := object(jobs + '/inputs.json')!
		assert job_inputs['arch']!.str() == arch && job_inputs['family']!.str() == 'process-smp'
		assert job_inputs['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix')
		assert job_inputs['kernel_sha256']!.str() == digest(jobs + '/kernel/bin/vinix')
		assert job_inputs['source_sha256']!.str() == digest(root + 'tests/kernel-job-control/check.c')
		assert job_inputs['init_sha256']!.str() == digest(jobs + '/init')
		assert job_inputs['archive_sha256']!.str() == digest(jobs + '/initramfs.tar')
		job_log := os.read_file(jobs + '.log')!
		assert job_log.contains('JOB-CHECK DONE failures=0') && job_log.contains('All requested guest verdicts passed.')
		assert !job_log.contains('JOB-CHECK FAIL') && !job_log.contains('KERNEL PANIC') && !job_log.contains('FATAL EXCEPTION')
		for marker in ['continued blocked message receiver restarts without losing message',
			'caught SA_RESTART handler preserves blocking child wait', 'caught handler without SA_RESTART interrupts child wait',
			'400 stop/continue cycles preserve wait state and bounded storage'] { assert job_log.contains('JOB-CHECK PASS ' + marker) }
		publish(jobs + '/inputs.json', out + 'sysnr-jobs-' + arch + '.json')!
		publish(jobs + '.log', out + 'sysnr-jobs-' + arch + '.log')!
		for name in ['inputs.json', 'init', 'initramfs.tar', 'test.iso'] { artifacts['jobs_' + name] = digest(jobs + '/' + name) }
		artifacts['jobs_log'] = digest(jobs + '.log')
		artifacts['job_fixture'] = digest(root + 'tests/kernel-job-control/check.c')
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['job_controller'] = digest(root + 'build-support/native-compat-tools/main.v')
		artifacts['host_tests'] = digest(area + 'host-tests.log')
		artifacts['audit'] = digest(@FILE)
		record := Evidence{arch, 'Native UID1000 musl ELF64: seven selector/private-slot/filter/TRAP/strict/SA_RESTART groups; eight regression cases and four-CPU job-control suite. Low32 dispatch, signed metadata, full original register state. No native ELF32/x32 or foreign ABI qualification', 'ee6a8aae', artifacts, inputs}
		os.write_file(out + 'sysnr-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'sysnr-host-tests.log')!
	println('Native syscall selectors, private verdict isolation and preserved restart state: verified')
}
