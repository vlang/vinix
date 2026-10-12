// Use -nocache -cflags -O2; -prod must fail the assertion control.
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
	assert inventory.len == 54
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	for path, hash in inventory { assert digest(root + path) == hash }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', '--short=8', 'HEAD'])! == 'e12b3a44'
		assert git(tree, ['diff', '--name-only', 'HEAD'])!.split_into_lines() == [
			'kernel/proc/container.v', 'kernel/proc/proc_amd64.v', 'kernel/proc/proc_arm64.v',
			'kernel/sched/sched_amd64.v', 'kernel/sched/sched_arm64.v', 'kernel/syscall/table/container.v']
		assert git(tree, ['ls-files', '--others', '--exclude-standard', '--', 'kernel/proc'])! == 'kernel/proc/securebits.v'
		for path, hash in inventory { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		for signature in ['void proc__securebits_after_exec(void)', 'u32 proc__securebits_state(proc__Thread* task)',
			'bool proc__set_keepcaps(bool value)', 'bool proc__set_securebits(u64 value)'] {
			body := generated.all_after(signature + ' {').all_before('\n}\n')
			assert body.len > 0 && !body.contains('__ptr_eq') && !body.contains('array_eq')
			assert !body.contains('malloc') && !body.contains('memdup') && !body.contains('new_array')
		}
		assert generated.contains('katomic__load_T_u32(&task->securebits)')
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + (if phase == 'before' { 'before4-' } else { 'after3-' }) + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			kernel := receipt['kernel_sha256']!.str()
			assert kernel == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert kernel == digest(tree + 'kernel/bin/vinix') }
			else { assert kernel == digest(area + 'before-kernel-' + suffix + '/bin/vinix') }
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else { 3 }
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
				assert names == ['securebits']
				assert log.contains('LINUX SECUREBITS FAIL: option=28 value=256 actual=0/0 expected=-1/1')
				assert !log.split_into_lines().any(it.trim_space() == 'LINUX SECUREBITS: PASS')
			} else {
				assert names == ['securebits', 'keepcaps', 'nnpthread']
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				assert log.contains('LINUX SECUREBITS PASS: four lock pairs, exact refusals, UID and ambient policy, exec preservation')
				assert log.contains('LINUX SECUREBITS PASS: sibling independence and clone/fork/exec inheritance')
				assert log.count('LINUX SECUREBITS CHILD: exec flags and locks') == 11
				assert log.contains('Linux compatibility guest suite: PASS') && !log.contains('LINUX SECUREBITS FAIL')
			}
			label := 'securebits-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
			artifacts[phase + '_kernel'] = kernel
		}
		assert artifacts['before_kernel'] != artifacts['after_kernel']
		cap := area + 'cap-' + suffix
		receipt := object(cap + '/inputs.json')!
		assert receipt['suite']!.str() == 'capability-exec' && receipt['native_guest_returncode']!.int() == 0
		assert receipt['selected_kernel_sha256']!.str() == artifacts['after_kernel']
		assert digest(cap + '/kernel/bin/vinix') == artifacts['after_kernel']
		assert receipt['iso_sha256']!.str() == digest(cap + '/test.iso')
		assert receipt['fixture_elf_sha256']!.str() == digest(cap + '/init')
		assert receipt['source_sha256']!.as_map()['guest.c']!.str() == digest(root + 'tests/capability-exec/guest.c')
		log := os.read_file(cap + '.log')!
		assert log.contains('CAP EXEC GUEST: PASS') && log.count('CAP EXEC PASS:') == 7 && !log.contains('CAP EXEC FAIL')
		publish(cap + '/inputs.json', out + 'securebits-cap-' + arch + '.json')!
		publish(cap + '.log', out + 'securebits-cap-' + arch + '.log')!
		artifacts['capability_receipt'] = digest(cap + '/inputs.json')
		artifacts['capability_log'] = digest(cap + '.log')
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['kernel_v_compiler'] = digest(area + 'v')
		artifacts['build_log'] = digest(area + 'after-build-' + suffix + '.log')
		artifacts['audit'] = digest(@FILE)
		artifacts['controller'] = digest(root + 'tests/linux-compat/run.v')
		artifacts['host_tests'] = digest(area + 'host-tests.log')
		record := Evidence{arch, 'Native musl ELF64 securebits: task-local behavior/lock pairs, exact permission/mask/lock errors, KEEP_CAPS interoperability, root exec and UID/ambient capability effects, sibling/clone/fork/nonleader-exec checks and eleven exec probes; independent lifetime review; no new allocations/frees; capability sets remain process-wide', 'e12b3a44', artifacts, inventory}
		encoded := json2.encode(record, prettify: true) + '\n'
		path := out + 'securebits-' + arch + '-evidence.json'
		if os.exists(path) { assert os.read_file(path)! == encoded } else { os.write_file(path, encoded)! }
	}
	publish(area + 'host-tests.log', out + 'securebits-host-tests.log')!
	println('Native securebits policy, task ownership and regression evidence: verified')
}
