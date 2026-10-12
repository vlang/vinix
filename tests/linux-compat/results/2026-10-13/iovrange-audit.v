// Compile without -prod: deliberate assertion failures must execute.
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
	assert log.contains('LINUX IOVRANGE MUTATION: kind=0 write=0 count=2 variant=0 byte=41 offset_or_queued=1'), 'native failure markers required'
	for count in [2, 8, 9, 513, 1024] {
		for kind in 0 .. 4 {
			assert log.contains('LINUX IOVRANGE DETAIL: label=' + (kind * 10).str() + ' write=0 count=' + count.str() + ' result=1/0 expected=-1/14')
			assert log.contains('LINUX IOVRANGE DETAIL: label=' + (kind * 10).str() + ' write=1 count=' + count.str() + ' result=1/0 expected=-1/14')
			assert log.contains('LINUX IOVRANGE DETAIL: label=' + (kind * 10 + 3).str() + ' write=0 count=' + count.str() + ' result=-1/22 expected=-1/14')
		}
	}
	assert log.contains('LINUX IOVRANGE DETAIL: label=101 write=0 count=1 result=-1/14 expected=0/0')
	assert log.contains('LINUX IOVRANGE DETAIL: label=103 write=0 count=1 result=-1/14 expected=0/0')
	for ordinary in 0 .. 2 { assert log.contains('LINUX IOVRANGE CASE: ordinary=' + ordinary.str() + ' checks=215 failures=121') }
	assert log.contains('LINUX IOVRANGE FAIL: native range/error/count semantics')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVRANGE: PASS')
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
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovrange-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-pass-control', area + 'after-final-arm.log'], 'native failure markers required')
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 62
	for path, hash in inputs { if !path.starts_with('kernel/') || path == 'kernel/syscall/table/linux_common.v' { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'geometry-host-tests.log')!.contains('Mapping metadata storage admission: PASS')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '655 source files, 406 allocation sites', 'x86_64': '651 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)')
		assert after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	// Preserve the rejected 47-bit x86 fixture, rather than count its other
	// successful cases as qualification for the corrected limit oracle.
	rejected := object(area + 'after-x86/receipt.json')!
	assert rejected['architecture']!.str() == 'x86_64'
	rejected_first := rejected['results']!.as_array()[0].as_map()
	assert rejected_first['name']!.str() == 'iovrange' && rejected_first['exit_code']!.int() == 1
	assert rejected_first['source_sha256']!.str() == digest(area + 'after-x86/sources/iovrangefixture/core.v')
	assert rejected_first['init_sha256']!.str() == digest(area + 'after-x86/iovrange/init')
	assert rejected_first['iso_sha256']!.str() == digest(area + 'after-x86/iovrange/test.iso')
	assert rejected_first['source_sha256']!.str() != digest(root + 'tests/linux-compat/iovrangefixture/core.v')
	assert os.read_file(area + 'after-x86/sources/iovrangefixture/core.v')!.contains('const user_limit = u64(1) << 47')
	assert os.read_file(area + 'after-x86.log')!.contains('LINUX IOVRANGE CASE: ordinary=0 checks=215 failures=21')
	assert rejected['kernel_sha256']!.str() == digest(area + 'kernel-x86/kernel/bin/vinix')
	publish(area + 'after-x86/receipt.json', out + 'iovrange-rejected-limit-x86_64.json')!
	publish(area + 'after-x86.log', out + 'iovrange-rejected-limit-x86_64.log')!
	interrupted := os.read_file(area + 'after-final-x86.log')!
	assert interrupted.contains('failed to open file') && interrupted.contains('after-final-x86/receipt.json')
	assert interrupted.contains('LINUX IOVRANGE: PASS') && !os.exists(area + 'after-final-x86/receipt.json')
	publish(area + 'after-final-x86.log', out + 'iovrange-rejected-receipt-x86_64.log')!
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == '5cfff48012af3f6466d693b84557bdd3e88a573c'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_common.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		importer := definition(generated, 'table__import_linux_iov')
		assert importer.count('usercopy__copy_from_user(') == 1 && importer.count('memory__malloc_packed_fallible(') == 1
		assert importer.count('table__LinuxIOVector__release(vector);') == 3
		assert importer.contains('vector.owned = true;') && importer.contains('.value = vector')
		assert !importer.contains('memdup(') && !importer.contains('array_new(')
		assert importer.contains('memory__page_size') && importer.contains('memory__user_address_limit()')
		assert importer.contains('((iov.base > limit) || (length > (limit - iov.base)))')
		assert importer.contains('iovcnt == 1') && importer.contains('((vector.data)[i]).len = taken;')
		assert importer.contains('max_count - vector.total') && importer.contains('vector.total += taken')
		length_check := importer.index('errno__einval') or { panic('missing length checks') }
		count_cap := importer.index('u64 max_count') or { panic('missing cap') }; assert length_check < count_cap
		release := definition(generated, 'table__LinuxIOVector__release')
		free_data := release.index('v_free(vector.data);') or { panic('missing free') }
		free_charge := release.index('kbudget__release(vector.charge);') or { panic('missing charge release') }; assert free_data < free_charge
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + phase + if phase == 'after' && suffix == 'x86' { '-final2-' } else { '-final-' } + suffix
			receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'iovimport-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			mut rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else if arch == 'x86_64' { 8 } else { 11 }
			if phase == 'after' && arch == 'x86_64' {
				failed := rows[7].as_map()
				assert failed['name']!.str() == 'sharedmem' && failed['exit_code']!.int() == 1
				assert failed['detail']!.str() == 'Command failed' && failed['iso_sha256']!.str() == ''
				assert failed['source_sha256']!.str() == digest(state + '/sources/sharedmemfixture/core.v')
				assert failed['init_sha256']!.str() == digest(state + '/sharedmem/init')
				assert os.read_file(state + '.log')!.contains('No space left on device')
				rows = rows[..7]
			}
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init') && item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				fixture := os.read_file(state + '/' + name + '/fixture.c')!
				if name == 'iovrange' {
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index') && !fixture.contains('malloc(')
					assert definition(fixture, 'iovrangefixture__limits').count('alloca(') == 1
					assert definition(fixture, 'iovrangefixture__range_case').count('alloca(') == 1
					assert definition(fixture, 'iovrangefixture__storage').count('alloca(') == 2
					probe := definition(fixture, 'iovrangefixture__native_limit')
					assert probe.count('mmap(') == if arch == 'aarch64' { 2 } else { 3 }
					assert probe.count('munmap(') == if arch == 'aarch64' { 2 } else { 3 }
					assert probe.contains('MAP_FIXED_NOREPLACE') && probe.contains('last_page=mapped next_page=refused')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			mut log := os.read_file(state + '.log')!
			if phase == 'after' && arch == 'x86_64' {
				resumed := area + 'after-rest-x86'
				retry := object(resumed + '/receipt.json')!
				assert retry['architecture']!.str() == arch && retry['kernel_sha256']!.str() == receipt['kernel_sha256']!.str()
				assert retry['kernel_sha256']!.str() == digest(resumed + '/kernel/bin/vinix')
				more := retry['results']!.as_array(); assert more.len == 4
				for row in more {
					item := row.as_map(); name := item['name']!.str(); names << name
					assert item['exit_code']!.int() == 0
					assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
					assert item['source_sha256']!.str() == digest(resumed + '/sources/' + name + 'fixture/core.v')
					assert item['init_sha256']!.str() == digest(resumed + '/' + name + '/init')
					assert item['iso_sha256']!.str() == digest(resumed + '/' + name + '/test.iso')
					artifacts['after_' + name + '_generated_c'] = digest(resumed + '/' + name + '/fixture.c')
				}
				log += '\n' + os.read_file(resumed + '.log')!
				artifacts['resumed_receipt'] = digest(resumed + '/receipt.json'); artifacts['resumed_log'] = digest(resumed + '.log')
				publish(resumed + '/receipt.json', out + 'iovrange-resumed-x86_64.json')!
				publish(resumed + '.log', out + 'iovrange-resumed-x86_64.log')!
			}
			assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			if phase == 'before' { assert names == ['iovrange']; native_failure(log) }
			else {
				assert names == ['iovrange', 'iovimport', 'iovpin', 'pathio', 'readerror', 'pipezero', 'open', 'sharedmem', 'runtime', 'seccomp', 'futexqueue']
				assert !log.contains('LINUX IOVRANGE FAIL') && !log.contains('LINUX IOVRANGE DETAIL') && !log.contains('LINUX IOVRANGE MUTATION')
				for ordinary in 0 .. 2 { assert log.contains('LINUX IOVRANGE CASE: ordinary=' + ordinary.str() + ' checks=215 failures=0') }
				assert log.contains('LINUX IOVRANGE LIMIT: page=' + if arch == 'aarch64' { '16384 max_rw_count=2147467264' } else { '4096 max_rw_count=2147479552' } + ' checks=14 PASS')
				assert log.contains('LINUX IOVRANGE ADDRESS: user_limit=' + if arch == 'aarch64' { '140737488355328' } else { '72057594037927936' } + ' last_page=mapped next_page=refused')
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				for marker in ['IOVRANGE', 'IOVIMPORT', 'IOVPIN'] { retention(log, arch, marker) }
			}
			label := 'iovrange-' + phase + '-' + arch; publish(state + '/receipt.json', out + label + '.json')!; publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str(); artifacts[phase + '_receipt'] = digest(state + '/receipt.json'); artifacts[phase + '_log'] = digest(state + '.log')
		}
		assert artifacts['before_iovrange_generated_c'] == artifacts['after_iovrange_generated_c']
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c'); artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(area + 'run'); artifacts['audit'] = digest(@FILE)
		if arch == 'x86_64' { artifacts['rejected_limit_receipt'] = digest(area + 'after-x86/receipt.json'); artifacts['rejected_limit_log'] = digest(area + 'after-x86.log'); artifacts['interrupted_receipt_log'] = digest(area + 'after-final-x86.log') }
		for label in ['host-tests', 'geometry-host-tests', 'allocs-before', 'allocs-after'] { artifacts[label] = digest(area + label + '.log') }
		evidence := Evidence{arch, 'Native musl ELF64 root/UID1000: 430 range/length/error/count checks across regular files, pipes, UNIX stream/datagram sockets and 2/8/9/513/1024-entry imports. Fixed mmap probes measure the active address limit (47-bit ARM, 56-bit x86 QEMU), map its last page and refuse the next. Unchanged kernels fail 121 cases per credential cohort and consume/mutate original resources; fixed kernels preserve offsets, bytes and queues. EOF boundary tests verify one-segment page-size MAX_RW_COUNT truncation before range checks; multi-segment original ranges and zero tails are checked before I/O. Two 200-cycle error/count cohorts retain flat slab classes/big pages; header/descriptor race cases remain passing. Eleven cases pass; x86 uses seven completed cases plus four resumed cases against the identical frozen kernel, preserving its original failed sharedmem staging row. Host/geometry checks pass; existing allocation allowances still fail identically. No 2 GiB payload transfer, positioned vectors, tagged ARM addresses, four-level x86 run, shared-offset atomicity, stream message conformance, exhaustion or foreign ABI qualification', '5cfff48012af3f6466d693b84557bdd3e88a573c', artifacts, inputs}
		os.write_file(out + 'iovrange-' + arch + '-evidence.json', json2.encode(evidence, prettify: true) + '\n')!
	}
	for label in ['host-tests', 'geometry-host-tests', 'allocs-before', 'allocs-after'] { publish(area + label + '.log', out + 'iovrange-' + label + '.log')! }
	println('Native vector range, length, bounded count, retention and unchanged allocation audit failures: verified')
}
