// Use -enable-globals -nocache -cflags -O2; -prod must fail the assertion control.
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
fn offset(source string, fragment string) int {
	return source.index(fragment) or { panic('missing generated fragment: ' + fragment) }
}
fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}
fn publish(source string, output string) ! {
	bytes := os.read_bytes(source)!
	if os.exists(output) { assert os.read_bytes(output)! == bytes }
	else { os.write_file_array(output, bytes)! }
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
	if '--negative-control' in os.args { assert false, 'receipt audit failure must be fatal'; return }
	mut control := os.new_process(os.executable())
	control.set_args(['--negative-control'])
	control.set_redirect_stdio()
	control.run()
	message := control.stdout_slurp() + control.stderr_slurp()
	control.wait()
	code := control.code
	control.close()
	if code != 1 || !message.contains('receipt audit failure must be fatal') { panic('audit assertions must execute; compile without -prod') }
	root := '/Users/alex/code/vinix/'
	area := '/Volumes/VinixSecureBits1012/'
	out := root + 'tests/linux-compat/results/2026-10-12/'
	inventory := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inventory.len == 55
	assert os.read_file(area + 'cappid-host-tests55.log')!.contains('8 passed, 8 total')
	for path, hash in inventory { assert digest(root + path) == hash }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'cappid-kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == 'e12b3a44'
		assert git(tree, ['diff', '--name-only', 'HEAD'])!.split_into_lines() == [
			'kernel/proc/container.v', 'kernel/proc/proc_amd64.v', 'kernel/proc/proc_arm64.v',
			'kernel/sched/sched_amd64.v', 'kernel/sched/sched_arm64.v', 'kernel/syscall/table/container.v']
		assert git(tree, ['ls-files', '--others', '--exclude-standard', '--', 'kernel/proc'])! == 'kernel/proc/securebits.v'
		for path, hash in inventory { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		assert generated.contains('arg4 != 0') && generated.contains('arg5 != 0') && generated.contains('arg2 == 4')
		drop := generated.all_after('} else if (option == table__pr_capbset_drop) {').all_before('} else if (option == table__pr_set_keepcaps)')
		assert offset(drop, 'proc__has_capability') < offset(drop, 'arg2 >')
		assert offset(drop, 'errno__eperm') < offset(drop, 'errno__einval')
		assert !drop.contains('malloc') && !drop.contains('memdup') && !drop.contains('new_array')
		capset := generated.all_after('multi_return_u64_u64 table__syscall_linux_capset(void* _0, u64 header_ptr, u64 data_ptr) {').all_before('\n}\n')
		assert capset.contains('caps.inheritable | caps.bounding')
		assert offset(capset, 'proc__has_capability(process, proc__cap_setpcap)') < offset(capset, 'caps.effective =')
		guards := capset.all_after('proc__Capabilities caps = process->caps;').all_before('caps.effective =')
		assert guards.contains('caps.bounding') && guards.contains('caps.permitted')
		assert !guards.contains('malloc') && !guards.contains('memdup') && !guards.contains('new_array')
		assert capset.contains('proc__own_tid(caller)') && !capset.contains('table__cap_target(')
		assert offset(capset, 'proc__own_tid(caller)') < offset(capset, 'data_ptr')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + 'cappid-' + phase + '-' + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			kernel := receipt['kernel_sha256']!.str()
			assert kernel == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert kernel == digest(tree + 'kernel/bin/vinix') }
			else {
				assert kernel == digest(area + 'capset-kernel-' + suffix + '/kernel/bin/vinix')
				previous := object(out + 'capset-after-' + arch + '.json')!
				assert previous['kernel_sha256']!.str() == kernel
			}
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else { 7 }
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
				if name in ['capset', 'cappid'] {
					fixture := os.read_file(state + '/' + name + '/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			log := os.read_file(state + '.log')!
			assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			if phase == 'before' {
				assert names == ['cappid']
				assert log.contains('LINUX CAPPID FAIL: version=429392688 pid=-1 data=')
				assert log.contains(' actual=-1/3 expected=-1/1')
				assert !log.split_into_lines().any(it.trim_space() == 'LINUX CAPPID: PASS')
			} else {
				assert names == ['cappid', 'capset', 'capbset', 'ambient', 'securebits', 'keepcaps', 'nnpthread']
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				assert log.contains('LINUX AMBIENT PASS: 81 exact errors, full-width reserved arguments and unchanged state')
				assert log.contains('LINUX CAPBSET PASS: 42 exact errors, effective permission precedence, unchanged sets and full-width arguments')
				assert log.contains('LINUX CAPBSET PASS: low/high idempotent drops, fork isolation and exec inheritance')
				assert log.count('LINUX CAPBSET CHILD:') == 2 && !log.contains('LINUX CAPBSET FAIL')
				assert log.count('LINUX CAPSET CASE:') == 13 && !log.contains('LINUX CAPSET MISMATCH') && !log.contains('LINUX CAPSET FAIL')
				assert log.contains('LINUX CAPSET PASS: 13 isolated cases, low/high bounding restrictions and effective CAP_SETPCAP authorization')
				assert log.contains('LINUX CAPSET PASS: failed updates preserve sets; inherited exceptions and ambient intersections')
				assert log.contains('LINUX CAPPID PASS: 236 exact errors, three versions, PID permission before data faults')
				assert log.count('LINUX CAPPID PASS: level=') == 2 && !log.contains('LINUX CAPPID FAIL')
				for level in ['0', '1'] { assert log.contains('LINUX CAPPID PASS: level=' + level + ' leader and sibling self IDs, exact refusals and unchanged sets') }
				assert log.count('LINUX SECUREBITS CHILD: exec flags and locks') == 11
				assert log.contains('Linux compatibility guest suite: PASS') && !log.contains('LINUX AMBIENT FAIL')
			}
			label := 'cappid-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
			artifacts[phase + '_kernel'] = kernel
		}
		assert artifacts['before_kernel'] != artifacts['after_kernel']
		cap := area + 'cappid-cap-' + suffix
		receipt := object(cap + '/inputs.json')!
		assert receipt['suite']!.str() == 'capability-exec' && receipt['native_guest_returncode']!.int() == 0
		assert receipt['selected_kernel_sha256']!.str() == artifacts['after_kernel']
		assert digest(cap + '/kernel/bin/vinix') == artifacts['after_kernel']
		assert receipt['iso_sha256']!.str() == digest(cap + '/test.iso')
		assert receipt['fixture_elf_sha256']!.str() == digest(cap + '/init')
		assert receipt['source_sha256']!.as_map()['guest.c']!.str() == digest(root + 'tests/capability-exec/guest.c')
		log := os.read_file(cap + '.log')!
		assert log.contains('CAP EXEC GUEST: PASS') && log.count('CAP EXEC PASS:') == 7 && !log.contains('CAP EXEC FAIL')
		publish(cap + '/inputs.json', out + 'cappid-cap-' + arch + '.json')!
		publish(cap + '.log', out + 'cappid-cap-' + arch + '.log')!
		artifacts['capability_receipt'] = digest(cap + '/inputs.json')
		artifacts['capability_log'] = digest(cap + '.log')
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['kernel_v_compiler'] = digest(area + 'v-snapshot/v-isolated')
		artifacts['build_log'] = digest(area + 'cappid-build-' + suffix + '.log')
		artifacts['audit'] = digest(@FILE)
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['host_tests'] = digest(area + 'cappid-host-tests55.log')
		record := Evidence{arch, 'Native musl ELF64 capset caller PID validation: 236 exact errors across three capability versions, root and UID 1000 leaders/siblings, zero/self no-op updates, other-PID EPERM before data faults, unchanged sets and no target lookup; capset/bounding/ambient/securebits/KEEPCAPS/no_new_privs and capability-exec regressions; capability sets remain process-wide', 'e12b3a44', artifacts, inventory}
		encoded := json2.encode(record, prettify: true) + '\n'
		path := out + 'cappid-' + arch + '-evidence.json'
		if os.exists(path) { assert os.read_file(path)! == encoded } else { os.write_file(path, encoded)! }
	}
	publish(area + 'cappid-host-tests55.log', out + 'cappid-host-tests.log')!
	println('Native capset caller PID and error precedence evidence: verified')
}
