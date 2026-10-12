// Compile without -prod: a deliberate failing assertion must execute.
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
	if os.exists(output) { assert os.read_bytes(output)! == data } else { os.write_file_array(output, data)! }
}
fn git(tree string, args []string) !string {
	mut command := ['-C', tree]; command << args
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0; return output.trim_space()
}
fn definition(source string, name string) string {
	lines := source.split_into_lines().filter(it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
}
fn native_failure(log string) {
	assert log.contains('LINUX IOVIMPORT DETAIL: read count=2 protect=0 result=2/0 bytes=41,00 alternate=42'), 'native failure markers required'
	for count in [2, 8, 9, 513, 1024] {
		assert log.contains('LINUX IOVIMPORT DETAIL: read count=' + count.str() + ' protect=1 result=-1/14 bytes=41,00 alternate=00')
		assert log.contains('LINUX IOVIMPORT DETAIL: write count=' + count.str() + ' protect=0 result=1052673/0 bytes=1052673 content=0')
		assert log.contains('LINUX IOVIMPORT DETAIL: write count=' + count.str() + ' protect=1 result=1048577/0 bytes=1048577 content=1')
	}
	for ordinary in 0 .. 2 { for round in 0 .. 2 {
		assert log.contains('LINUX IOVIMPORT ROUND: ordinary=' + ordinary.str() + ' round=' + round.str() + ' failures=' + ((round + 1) * 20).str())
	} }
	assert log.contains('LINUX IOVIMPORT FAIL: vector snapshot or retirement')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVIMPORT: PASS')
}
fn retention(log string, arch string, marker string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX ' + marker + ' SLAB:') && !line.starts_with('LINUX ' + marker + ' STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7
		group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0].u64() == pair[1].u64()
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'
			seen[key] = true; rows[group]++
		} else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; pages[group]++ }
	}
	for group in 0 .. 2 { assert rows[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	control(['--negative-control'], 'audit assertions must execute')
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovimport-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required')
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 62
	for path, hash in inputs { if !path.starts_with('kernel/') || path == 'kernel/syscall/table/linux_common.v' { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'storage-host-final.log')!.contains('Mapping metadata storage admission: PASS')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '655 source files, 406 allocation sites', 'x86_64': '651 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)')
		assert after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == 'e7404c86d50f518cf2e1dd2d58d742fd15b66132'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_common.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		importer := definition(generated, 'table__import_linux_iov')
		assert importer.count('usercopy__copy_from_user(') == 1
		assert importer.count('memory__malloc_packed_fallible(') == 1
		assert importer.count('table__LinuxIOVector__release(vector);') == 2
		assert importer.contains('vector.owned = true;') && importer.contains('.value = vector')
		assert !importer.contains('memdup(') && !importer.contains('array_new(')
		geometry := importer.index('vmstorage__allocation_bytes(bytes)') or { panic('missing geometry') }
		admission := importer.index('proc__reserve_kernel(') or { panic('missing admission') }
		allocation := importer.index('memory__malloc_packed_fallible(') or { panic('missing allocation') }
		assert geometry < admission && admission < allocation
		release := definition(generated, 'table__LinuxIOVector__release')
		assert release.contains('if (vector.owned)') && release.contains('v_free(vector.data);')
		free_data := release.index('v_free(vector.data);') or { panic('missing free') }
		free_charge := release.index('kbudget__release(vector.charge);') or { panic('missing charge release') }
		assert free_data < free_charge
		for name in ['table__syscall_linux_readv', 'table__syscall_linux_writev'] {
			vector := definition(generated, name)
			assert vector.count('file__fd_from_fdnum(') == 1 && vector.count('table__import_linux_iov(') == 1
			assert vector.contains('vinix_stack_alloc(') && vector.contains('(vector.data)[i]')
			assert !vector.contains('table__read_linux_iov(') && !vector.contains('table__validate_linux_iov(')
			permission := vector.index('table__linux_iov_access_error(') or { panic('missing access check') }
			import_at := vector.index('table__import_linux_iov(') or { panic('missing vector import') }
			assert permission < import_at
			assert vector.contains('table__LinuxIOVector__release(vector);') && vector.contains('file__FD__unref(fd);')
		}
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix; receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'iovpin-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 10 }
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init') && item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				if name == 'iovimport' {
					fixture := os.read_file(state + '/iovimport/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index') && !fixture.contains('malloc(')
					assert definition(fixture, 'iovimportfixture__abandon').contains('_exit(2)')
					assert definition(fixture, 'iovimportfixture__storage').count('alloca(') == 2
					assert definition(fixture, 'iovimportfixture__storage_cycle').count('alloca(') == 1
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			log := os.read_file(state + '.log')!; assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			retention(log, arch, 'IOVIMPORT')
			if phase == 'before' { assert names == ['iovimport']; native_failure(log) }
			else {
				assert names == ['iovimport', 'iovpin', 'pathio', 'readerror', 'pipezero', 'open', 'sharedmem', 'runtime', 'seccomp', 'futexqueue']
				assert !log.contains('LINUX IOVIMPORT FAIL') && !log.contains('LINUX IOVIMPORT DETAIL')
				for ordinary in 0 .. 2 { assert log.contains('LINUX IOVIMPORT CASE: ordinary=' + ordinary.str() + ' reads=20 writes=20 PASS') }
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				retention(log, arch, 'IOVPIN')
			}
			label := 'iovimport-' + phase + '-' + arch; publish(state + '/receipt.json', out + label + '.json')!; publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str(); artifacts[phase + '_receipt'] = digest(state + '/receipt.json'); artifacts[phase + '_log'] = digest(state + '.log')
		}
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c'); artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(area + 'run'); artifacts['host_tests'] = digest(area + 'host-tests.log'); artifacts['geometry_host_tests'] = digest(area + 'storage-host-final.log')
		artifacts['allocation_audit_before'] = digest(area + 'allocs-before.log'); artifacts['allocation_audit_after'] = digest(area + 'allocs-after.log'); artifacts['audit'] = digest(@FILE)
		evidence := Evidence{arch, 'Native musl ELF64 root/UID1000: 40 blocked readv and 40 multi-chunk writev calls use copied readonly 2/8/9/513/1024-entry headers after mutation or protection. Unchanged controls redirect reads/writes or return late EFAULT/short success. Two 200-cycle cohorts retain flat slab classes/big pages across stack/heap imports, copy/length/payload errors and valid/empty returns. Ten regression cases. Geometry host tests pass; existing 406 ARM/295 x86 allocation allowance failures are unchanged. Positioned vectors, Linux MAX_RW_COUNT/range semantics, shared-offset atomicity, stream message semantics, actual memory exhaustion and foreign ABI remain separate', 'e7404c86d50f518cf2e1dd2d58d742fd15b66132', artifacts, inputs}
		os.write_file(out + 'iovimport-' + arch + '-evidence.json', json2.encode(evidence, prettify: true) + '\n')!
	}
	for input, label in {'host-tests': 'host-tests', 'storage-host-final': 'geometry-host-tests', 'allocs-before': 'allocs-before', 'allocs-after': 'allocs-after'} { publish(area + input + '.log', out + 'iovimport-' + label + '.log')! }
	println('Native immutable vector imports, retention, geometry and unchanged allocation audit failures: verified')
}
