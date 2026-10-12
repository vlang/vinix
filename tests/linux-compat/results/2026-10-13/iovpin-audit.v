// Compile without -prod; deliberately failing controls prove active checks.
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
fn definition(text string, name string) string {
	lines := text.split_into_lines().filter(it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1
	return text.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
}
fn native_failure(log string) {
	assert log.contains('LINUX IOVPIN DETAIL: write kind=0'), 'native failure markers required'
	assert log.contains('original=1048577 replacement=4096')
	assert log.contains('LINUX IOVPIN DETAIL: read kind=0 result=2/0 bytes=41,58')
	assert log.contains('LINUX IOVPIN DETAIL: read kind=3 result=1/0 bytes=41,00')
	assert log.contains('LINUX IOVPIN FAIL: vector descriptor identity or reference release')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVPIN: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}
	mut rows := [2]int{}
	mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX IOVPIN SLAB:') && !line.starts_with('LINUX IOVPIN STORAGE:') { continue }
		fields := line.fields()
		assert fields.len == 7
		group := fields[3].all_after('=').int()
		assert group in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit()))
		assert pair[0].u64() == pair[1].u64()
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]
			assert key !in seen && fields[6] == 'cycles=200'
			seen[key] = true; rows[group]++
		} else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; pages[group]++ }
	}
	for group in 0 .. 2 { assert rows[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-compile-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	control(['--negative-control'], 'audit assertions must execute')
	root := '/Users/alex/code/vinix/'
	area := '/tmp/vinix-iovpin-1013/'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-compile-control', area + 'before2-arm.log'], 'native failure markers required')
	publish(area + 'before2-arm.log', out + 'iovpin-rejected-compilation-aarch64.log')!
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
	assert inputs.len == 62
	for path, hash in inputs {
		if !path.starts_with('kernel/') || path in ['kernel/fs/vfs.v', 'kernel/syscall/table/linux_common.v'] { assert digest(root + path) == hash }
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == 'cfb62819fc28ec70dca9cf6f053d9c4d442eb26f'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/fs/vfs.v\nkernel/syscall/table/linux_common.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		for name in ['table__syscall_linux_readv', 'table__syscall_linux_writev'] {
			vector := definition(generated, name)
			assert vector.count('file__fd_from_fdnum(') == 1
			assert vector.contains('table__linux_iov_access_error(fd,')
			assert vector.contains('file__FD__unref(fd);')
			assert !vector.contains('fs__syscall_read(') && !vector.contains('fs__write_from_kernel(')
			assert !vector.contains('memdup(') && !vector.contains('array_new(')
			permission := vector.index('table__linux_iov_access_error') or { panic('missing access check') }
			validation := vector.index('table__validate_linux_iov') or { panic('missing vector import') }
			assert permission < validation
		}
		assert definition(generated, 'table__syscall_linux_readv').contains('fs__read_pinned_descriptor(fd,')
		assert definition(generated, 'table__syscall_linux_writev').count('fs__write_pinned_descriptor(fd,') == 2
		for name, event in {'fs__read_pinned_descriptor': 'fs__in_access', 'fs__write_pinned_descriptor': 'fs__in_modify'} {
			borrow := definition(generated, name)
			assert !borrow.contains('file__fd_from_fdnum(') && !borrow.contains('file__FD__unref(')
			assert !borrow.contains('memdup(') && !borrow.contains('malloc(')
			assert borrow.contains('resource__o_accmode') && borrow.contains('fs__inotify_emit(') && borrow.contains(event)
		}
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before4-' } else { 'after-final-' } + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch
			assert receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(root + 'tests/linux-compat/results/2026-10-12/pathio-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else { 9 }
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init')
				assert item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				if name == 'iovpin' {
					fixture := os.read_file(state + '/iovpin/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index')
					assert !fixture.contains('malloc(') && !fixture.contains('array_new(')
					assert definition(fixture, 'iovpinfixture__abandon').contains('_exit(2)')
					assert definition(fixture, 'iovpinfixture__storage').count('alloca(') == 2
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			log := os.read_file(state + '.log')!
			assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			retention(log, arch)
			for ordinary in 0 .. 2 {
				assert log.split_into_lines().any(it.contains('LINUX IOVPIN STORAGE: ordinary=' + ordinary.str() + ' cycles=200') && it.trim_space().ends_with('PASS'))
				if phase == 'after' { assert log.contains('LINUX IOVPIN CASE: ordinary=' + ordinary.str() + ' reads=16 writes=12 PASS') }
			}
			if phase == 'before' { assert names == ['iovpin']; native_failure(log) }
			else {
				assert names == ['iovpin', 'pathio', 'readerror', 'pipezero', 'open', 'sharedmem', 'runtime', 'seccomp', 'futexqueue']
				assert !log.contains('LINUX IOVPIN FAIL') && !log.contains('LINUX IOVPIN DETAIL')
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
			}
			label := 'iovpin-' + phase + '-' + arch
			publish(state + '/receipt.json', out + label + '.json')!
			publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str()
			artifacts[phase + '_receipt'] = digest(state + '/receipt.json')
			artifacts[phase + '_log'] = digest(state + '.log')
		}
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c')
		artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(area + 'run')
		artifacts['host_tests'] = digest(area + 'host-tests.log')
		artifacts['rejected_compilation_log'] = digest(area + 'before2-arm.log')
		artifacts['audit'] = digest(@FILE)
		evidence := Evidence{arch, 'Native musl ELF64 root/UID1000: 32 blocked readv and 24 multi-chunk writev calls retain the original open description through close/dup2; replacement pipes/files remain untouched and EOF verifies writer reference release. Two 200-cycle vector success/empty/invalid-header/invalid-payload/wrong-access cohorts retain no slab-class objects or big pages. Unchanged controls redirect data or return partial results. Nine regression cases. Foreign ABI, shared-offset atomicity, mutable-vector import and stream short-read behavior remain separate', 'cfb62819fc28ec70dca9cf6f053d9c4d442eb26f', artifacts, inputs}
		os.write_file(out + 'iovpin-' + arch + '-evidence.json', json2.encode(evidence, prettify: true) + '\n')!
	}
	publish(area + 'host-tests.log', out + 'iovpin-host-tests.log')!
	println('Native vector descriptor identity, reference retention and rejected compilation control: verified')
}
