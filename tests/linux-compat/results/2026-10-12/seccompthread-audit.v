// Compile with -enable-globals -nocache -cflags -O2, without -prod.
import crypto.sha256
import json2
import os
import strconv

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
fn command(args []string) !string {
	mut p := os.new_process(args[0]); p.set_args(args[1..]); p.set_redirect_stdio(); p.run()
	text := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(text) }; return text.trim_space()
}
fn body(text string, signature string) string {
	assert text.contains(signature)
	return text.all_after(signature).all_before('\n}\n')
}
fn allocation_counts(path string) !map[string]int {
	mut counts := map[string]int{}
	for line in os.read_file(path)!.split_into_lines() {
		location := line.all_before(' ').split(':')
		if location.len != 3 { continue }
		strconv.atoi(location[1]) or { continue }
		strconv.atoi(location[2]) or { continue }
		counts[location[0] + ' ' + line.all_after(' ')]++
	}
	return counts
}
fn check_churn(text string) {
	for cycle in 0 .. 2 {
		for size in [32, 64, 96, 128] {
			prefix := 'LINUX SECCOMPTHREAD SLAB: cycle=' + cycle.str() + ' size=' + size.str() + ' '
			rows := text.split_into_lines().filter(it.trim_space().starts_with(prefix))
			assert rows.len >= 1 && rows.all(it.trim_space().ends_with('delta=0'))
		}
		assert text.contains('LINUX SECCOMPTHREAD CHURN: cycle=' + cycle.str() + ' threads=200 filters=800 forced_exec=100')
	}
	for kind in 0 .. 11 { assert text.contains('LINUX SECCOMPTHREAD CASE: ' + kind.str() + ' PASS') }
	assert text.contains('LINUX SECCOMPTHREAD: PASS') && !text.contains('LINUX SECCOMPTHREAD FAIL')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'receipt audit failure must be fatal'; return }
	mut control := os.new_process(os.executable()); control.set_args(['--negative-control']); control.set_redirect_stdio(); control.run()
	message := control.stdout_slurp() + control.stderr_slurp(); control.wait(); code := control.code; control.close()
	if code != 1 || !message.contains('receipt audit failure must be fatal') { panic('audit assertions must execute; compile without -prod') }
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-seccomp-1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 60
	own_kernel := ['kernel/proc/container.v', 'kernel/proc/proc.v', 'kernel/proc/proc_amd64.v',
		'kernel/proc/proc_arm64.v', 'kernel/proc/seccomp.v', 'kernel/proc/thread_attach.v',
		'kernel/sched/sched_amd64.v', 'kernel/sched/sched_arm64.v', 'kernel/syscall/table/container.v',
		'kernel/syscall/table/syscall_table_arm64.v', 'kernel/syscall/table/trace_amd64.v', 'kernel/userland/exit.v']
	// Other sessions edit the shared checkout. Kernel fingerprints describe
	// the isolated qualification trees; only our edited paths must also match
	// the shared files. Unrelated procfs net/dev edits are excluded.
	for path, hash in inputs { if !path.starts_with('kernel/') || path in own_kernel { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests-final.log')!.contains('8 passed, 8 total')
	before_counts := allocation_counts(area + 'allocs-baseline.log')!
	after_counts := allocation_counts(area + 'allocs.log')!
	for site, count in after_counts { assert count <= before_counts[site] }
	// Existing allowance failures stay failures; only the isolated delta passes.
	assert os.read_file(area + 'allocs-baseline.log')!.contains('NEW:')
	assert os.read_file(area + 'allocs.log')!.contains('NEW:')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert command(['git', '-C', tree, 'rev-parse', '--short=8', 'HEAD'])! == '71d666c4'
		assert command(['git', '-C', tree, 'diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == own_kernel
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		for signature in ['u32 proc__seccomp_verdict(proc__Thread* task, u64 nr, u64 ip, u64* args) {',
			'u32 proc__seccomp_run(Array instructions, u32* data) {'] {
			function := body(generated, signature)
			for allocation in ['memdup(', 'array_new(', 'new_array', 'malloc('] { assert !function.contains(allocation) }
		}
		attach := body(generated, 'multi_return_u64_u64 proc__seccomp_attach(Array instructions, bool sync, bool sync_esrch) {')
		allocation := attach.index('memory__malloc_packed_fallible') or { panic('missing allocation') }
		locking := attach.index('klock__Lock__acquire') or { panic('missing publication lock') }
		assert allocation < locking
		assert attach.contains('proc__seccomp_ancestor') && attach.contains('proc__tid_in') && attach.contains('errno__esrch')
		assert attach.contains('path_total += task->seccomp->path_total + 4')
		put := body(generated, 'void proc__seccomp_put(proc__SeccompFilter* filter) {')
		assert put.contains('array__free(&head->instructions)') && put.contains('v_free(head)')
		stopped := body(generated, 'void userland__kill_sibling_threads(proc__Process* current_process, proc__Thread* current_thread) {')
		assert stopped.contains('proc__seccomp_release(')
		assert stopped.all_after('userland__stop_claimed_thread(').contains('proc__seccomp_release(')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before-final-' + suffix } else { 'after-' + suffix }
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
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
				if name == 'seccompthread' { assert !os.read_file(state + '/' + name + '/fixture.c')!.contains('memdup(') }
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			text := os.read_file(state + '.log')!
			assert !text.contains('KERNEL PANIC') && !text.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['seccompthread'] && text.contains('count=0 error=0 nnp=0 actual=-1/13 mode=2 nnp=0')
				assert !text.split_into_lines().any(it.trim_space() == 'LINUX SECCOMPTHREAD: PASS')
			} else {
				assert names == ['seccompthread', 'seccomp', 'seccompquery', 'nnpthread', 'securebits', 'capabi', 'runtime', 'futexqueue']
				check_churn(text)
				assert text.contains('Linux compatibility guest suite: PASS')
			}
			label := 'seccompthread-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str()
		}
		cap := area + 'cap-' + suffix
		cap_receipt := object(cap + '/inputs.json')!
		assert cap_receipt['native_guest_returncode']!.int() == 0
		assert cap_receipt['selected_kernel_sha256']!.str() == artifacts['after_kernel']
		assert os.read_file(cap + '.log')!.contains('CAP EXEC GUEST: PASS')
		publish(cap + '/inputs.json', out + 'seccompthread-cap-' + arch + '.json')!
		publish(cap + '.log', out + 'seccompthread-cap-' + arch + '.log')!
		artifacts['capability_receipt'] = digest(cap + '/inputs.json')
		artifacts['capability_log'] = digest(cap + '.log')
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['compiler'] = digest(area + 'v-snapshot/v')
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['host_tests'] = digest(area + 'host-tests-final.log')
		artifacts['audit'] = digest(@FILE)
		record := Evidence{arch, 'Native musl ELF64 task-local seccomp and TSYNC, ancestry/refusal atomicity, no_new_privs propagation, clone/fork/nonleader-exec, live/zombie procfs snapshots, exact path limit and concurrent clone/sync; 3200 filter installations in two storage cohorts with flat32/64/96/128 classes; strict/KILL_THREAD signal scope, user notifications, sandbox completeness and procfs tree reclamation remain separate', '71d666c4', artifacts, inputs}
		os.write_file(out + 'seccompthread-' + arch + '-evidence.json', json2.encode(record, prettify: true) + '\n')!
	}
	tracking := area + 'track-final-arm'
	tracking_receipt := object(tracking + '/receipt.json')!
	assert tracking_receipt['kernel_sha256']!.str() == digest(tracking + '/kernel/bin/vinix')
	assert tracking_receipt['results']!.as_array()[0].as_map()['exit_code']!.int() == 0
	check_churn(os.read_file(tracking + '.log')!)
	for input, output in {
		'host-tests-final.log': 'host-tests.log'
		'allocs.log': 'allocs.log'
		'allocs-baseline.log': 'allocs-baseline.log'
		'track-final-arm/receipt.json': 'tracking-aarch64.json'
		'track-final-arm.log': 'tracking-aarch64.log'
		'perf-retention.json': 'retention-aarch64.json'
		'perf-retention.log': 'retention-aarch64.log'
		'perf-desktop2.json': 'desktop-after-aarch64.json'
		'perf-desktop2.log': 'desktop-after-aarch64.log'
		'perf-desktop-baseline.json': 'desktop-before-aarch64.json'
		'perf-desktop-baseline.log': 'desktop-before-aarch64.log'
	} { publish(area + input, out + 'seccompthread-' + output)! }
	retention := json2.decode[json2.Any](os.read_file(area + 'perf-retention.json')!)!.as_array()
	ops := retention.filter(it.as_map()['report']!.str() == 'PERF-OPS')
	churn := retention.filter(it.as_map()['report']!.str() == 'PERF-CHURN')
	assert ops.len == 36 && ops.all(it.as_map()['bytes_per_op']!.str() == '0')
	assert churn.len == 4 && churn.all(it.as_map()['per_run_bytes']!.str() == '0')
	for phase in ['baseline', '2'] {
		text := os.read_file(area + 'perf-desktop' + if phase == 'baseline' { '-baseline.log' } else { '2.log' })!
		assert text.contains('the desktop was not ready after 1s')
		assert !text.split_into_lines().any(it.trim_space() == 'VINIX DESKTOP PERF: DONE')
	}
	println('Native task-local seccomp/TSYNC evidence: verified; existing allowance and desktop failures retained')
}
