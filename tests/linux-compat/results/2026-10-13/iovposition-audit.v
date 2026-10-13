// Compile without -prod: both deliberately failing controls must execute.
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
	assert lines.len == 1
	return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
}
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX IOVPOSITION OUTCOMES: ordinary=' + ordinary.str() + if passing {
			' descriptor=192/0 sentinel=48/0 range=100/0 normal=20/0 partial=4/0 overflow=4/0 limit_checks=28 failed_limit_groups=0'
		} else {
			' descriptor=192/148 sentinel=48/16 range=100/80 normal=20/0 partial=4/0 overflow=4/4 limit_checks=28 failed_limit_groups=2'
		})
	}
}
fn native_failure(log string) {
	assert log.contains('label=10 write=0 v=0 count=0 offset=5 result=0/0 expected=-1/9'), 'native failure markers required'
	assert log.contains('label=3 write=0 v=0 count=1 offset=5 result=-1/14 expected=-1/9')
	assert log.contains('label=100 write=0 v=0 count=2 offset=0 result=1/0 expected=-1/14')
	assert log.contains('LINUX IOVPOSITION MUTATION: range write=1 v=0 count=2 variant=0 byte=58')
	assert log.contains('label=220 write=0 v=0 count=2 offset=9223372036854775806 result=0/0 expected=-1/22')
	assert log.contains('label=220 write=1 v=0 count=2 offset=9223372036854775806 result=-1/27 expected=-1/22')
	assert log.contains('label=303 write=0 v=0 count=1 offset=0 result=-1/14 expected=0/0')
	assert log.contains('label=310 write=0 v=0 count=2 offset=0 result=0/0 expected=-1/14')
	outcomes(log, false)
	assert log.contains('LINUX IOVPOSITION FAIL: positioned vector errors, ranges or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVPOSITION: PASS')
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
fn stream_digest(path string) !string {
	mut input := os.open(path)!; defer { input.close() }
	mut state := sha256.new(); mut buffer := []u8{len: 1024 * 1024}
	for {
		count := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		assert state.write(buffer[..count])! == count
	}
	mut hash := []u8{len: 32}; state.checksum_into(mut hash); return hash.hex()
}
fn performance(root string, area string, out string, base string, inputs map[string]string) ! {
	mut artifacts := {'controller': digest(area + 'perf'), 'controller_source': digest(area + 'perf.v'),
		'desktop': digest(area + 'vinix-desktop'), 'cached_initramfs': stream_digest(root + 'build-support/init-aarch64/initramfs-desktop.tar')!,
		'extractor_source': digest(area + 'extract-desktop.v'), 'auditor': digest(@FILE)}
	assert digest(out + 'iovposition-performance.v') == artifacts['controller_source']
	assert digest(out + 'iovposition-extract-desktop.v') == artifacts['extractor_source']
	for phase in ['before', 'after'] {
		artifacts[phase + '_kernel'] = digest(if phase == 'before' { area + 'perf-before-kernel/bin/vinix' } else { area + 'kernel-arm/kernel/bin/vinix' })
		for suite in ['perf', 'desktop'] {
			prefix := suite + '-' + phase
			log := os.read_file(area + prefix + '.log')!; serial := os.read_file(area + prefix + '/serial.log')!
			assert log.contains(serial) && serial.contains('VINIX DESKTOP PERF: DONE')
			assert !serial.contains('PERF-ERROR') && !serial.contains('KERNEL PANIC') && !serial.contains('FATAL EXCEPTION')
			rows := json2.decode[json2.Any](os.read_file(area + prefix + '.json')!)!.as_array()
			if suite == 'perf' {
				ops := rows.filter(it.as_map()['report'] or { json2.Any('') }.str() == 'PERF-OPS')
				churn := rows.filter(it.as_map()['report'] or { json2.Any('') }.str() == 'PERF-CHURN')
				cache := rows.filter(it.as_map()['report'] or { json2.Any('') }.str() == 'PERF-CACHE')
				assert ops.len == 36 && churn.len == 4 && cache.len == 1
				for row in ops { entry := row.as_map(); assert entry['count']!.str() == '200' && entry['bytes_per_op']!.str() == '0' }
				for row in churn { entry := row.as_map(); assert entry['runs']!.str() == '300' && entry['retained_kb']!.str() == '0' && entry['per_run_bytes']!.str() == '0' }
				assert !serial.split_into_lines().any(it.starts_with('PERF-SLAB '))
				assert cache[0].as_map()['written_mb']!.str() == '32'
			} else {
				assert rows.len == 3
				for i, scenario in ['idle', 'apps', 'drag'] {
					entry := rows[i].as_map(); assert entry['scenario']!.str() == scenario && entry['round']!.int() == 1
					assert entry['seconds']!.str() == '5.0' && entry['processes']!.str().int() >= if scenario == 'apps' { 7 } else { 2 }
					artifacts[phase + '_' + scenario + '_screenshot'] = digest(area + prefix + '-shots/new-' + scenario + '-1.ppm')
				}
			}
			artifacts[prefix + '_json'] = digest(area + prefix + '.json'); artifacts[prefix + '_log'] = digest(area + prefix + '.log')
			artifacts[prefix + '_serial'] = digest(area + prefix + '/serial.log')
			publish(area + prefix + '.json', out + 'iovposition-' + prefix + '.json')!
			publish(area + prefix + '.log', out + 'iovposition-' + prefix + '.log')!
		}
	}
	artifacts['candidate_apps_png'] = digest(area + 'desktop-apps.png')
	publish(area + 'desktop-apps.png', out + 'iovposition-desktop-apps.png')!
	context := 'AArch64 QEMU cached desktop image, identical extracted 13MiB desktop and V performance controller before/after. All36 200-operation rows retain zero bytes and all4 300-process churn rows retain zero memory/slab objects; the32MiB cache workload records expected cache growth. Idle/apps/drag each pass one5-second sample; the7-process apps screenshot was inspected. These startup/retention checks do not qualify Linux application installation or lifecycle, foreign ABI/ELF32 paths, x86 desktop performance, physical hardware or a performance benchmark threshold. Shared cached archives were explicitly preserved; only disposable VM state was cleaned.'
	os.write_file(out + 'iovposition-performance-evidence.json', json2.encode(Evidence{'aarch64', context, base, artifacts, inputs}, prettify: true) + '\n')!
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	control(['--negative-control'], 'audit assertions must execute')
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovposition-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required')
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '7d01a61b4aa0aae61f6ce378101b3585fa8b0080'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 62
	for path, hash in inputs { assert digest(root + path) == hash }
	assert git(area + 'v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git(area + 'v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'geometry.log')!.contains('Mapping metadata storage admission: PASS')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '655 source files, 406 allocation sites', 'x86_64': '651 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == [
			'kernel/file/file.v', 'kernel/syscall/table/linux_common.v', 'kernel/syscall/table/linux_compat.v']
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		positioned := definition(generated, 'table__linux_positioned_iov')
		assert positioned.count('file__fd_from_fdnum(') == 1 && positioned.count('table__import_linux_iov(') == 1
		assert positioned.contains('vinix_stack_alloc(') && positioned.contains('(vector.data)[i]')
		assert positioned.contains('file__pread_pinned_descriptor(fd,') && positioned.contains('file__pwrite_pinned_descriptor(fd,')
		assert !positioned.contains('file__syscall_pread(') && !positioned.contains('file__syscall_pwrite(')
		assert !positioned.contains('copy_from_user(') && !positioned.contains('malloc(') && !positioned.contains('memdup(')
		assert positioned.contains('vector.total > ((u64)(0x7fffffffffffffff) - (u64)(offset))')
		lookup_at := positioned.index('file__fd_from_fdnum(') or { panic('lookup missing') }
		access_at := positioned.index('table__linux_iov_access_error(') or { panic('access check missing') }
		import_at := positioned.index('table__import_linux_iov(') or { panic('import missing') }
		operation_at := positioned.index('file__pwrite_pinned_descriptor(') or { panic('write missing') }
		assert lookup_at < access_at && access_at < import_at && import_at < operation_at
		for kind in ['pread', 'pwrite'] {
			helper := definition(generated, 'file__' + kind + '_pinned_descriptor')
			assert !helper.contains('file__fd_from_fdnum(') && !helper.contains('file__FD__unref(')
			assert helper.contains('kbudget__release(') && helper.contains('free(buffer)')
			v2 := definition(generated, 'table__syscall_linux_' + kind + 'v2')
			assert v2.contains('offset < -1') && v2.contains('offset == -1')
			assert v2.contains('table__syscall_linux_' + kind.all_after('p') + 'v(') && !v2.contains('copy_from_user(')
		}
		mut artifacts := {'compiler': digest(area + 'v-snapshot/v'), 'controller': digest(area + 'run'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host-tests': digest(area + 'host-tests.log'), 'geometry': digest(area + 'geometry.log'),
			'allocs-before': digest(area + 'allocs-before.log'), 'allocs-after': digest(area + 'allocs-after.log')}
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix + '/'
			receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash
			assert digest(state + 'kernel/bin/vinix') == kernel_hash
			log := os.read_file(area + phase + '-' + suffix + '.log')!
			artifacts[phase + '_kernel'] = kernel_hash
			artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(area + phase + '-' + suffix + '.log')
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 11 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v')
				assert entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'iovposition' {
					fixture := os.read_file(c)!
					assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('mprotect(') && fixture.contains('munmap(') && fixture.contains('setrlimit(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true); retention(log, arch, 'IOVPOSITION') }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == ['iovposition', 'iovoffset', 'iovrange', 'iovimport', 'iovpin', 'pathio', 'open', 'readerror', 'pipezero', 'runtime', 'sharedmem']
				for marker in ['IOVOFFSET', 'IOVRANGE', 'IOVIMPORT', 'IOVPIN'] { retention(log, arch, marker) }
			}
			publish(state + 'receipt.json', out + 'iovposition-' + phase + '-' + arch + '.json')!
			publish(area + phase + '-' + suffix + '.log', out + 'iovposition-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_iovposition_generated_c'] == artifacts['after_iovposition_generated_c']
		context := 'Native musl ELF64 root/UID1000 positioned-vector error/range/offset/import conformance: 396 checks per cohort, read-only fast/heap headers, partial payload preservation, unchanged cursor/data/pipe queues and flat 200-cycle storage. Unchanged controls fail 148 descriptor, 16 sentinel, 80 range and 4 aggregate-offset cases per cohort plus both 14-check EOF-cap groups; normal/partial controls pass. One FD and one vector import are verified in emitted code and independently reviewed; deterministic positioned close/dup2/header races remain separate qualification. Eleven guest regressions, eight host tests and storage geometry pass; existing allocation allowances fail unchanged (406 ARM/295 x86). Flags, character-device positioned I/O, GNU libc/foreign ABIs, actual cap-sized payload transfer, disk-backed vectors, shared-offset atomicity and allocator exhaustion remain unqualified.'
		os.write_file(out + 'iovposition-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'geometry', 'allocs-before', 'allocs-after'] { publish(area + name + '.log', out + 'iovposition-' + name + '.log')! }
	if '--native-only' in os.args { println('Native positioned-vector qualification audit: PASS'); return }
	performance(root, area, out, base, inputs)!
	println('Positioned-vector qualification audit: PASS')
}
