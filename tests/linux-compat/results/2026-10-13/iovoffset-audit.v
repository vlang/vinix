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
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		for name, count in {'NORMAL': 78, 'NEGATIVE': 252, 'SENTINEL': 18} {
			bad := if passing { 0 } else { match name { 'NORMAL' { 60 } 'NEGATIVE' { 144 } else { 14 } } }
			assert log.contains('LINUX IOVOFFSET ' + name + ': ordinary=' + ordinary.str() + ' cases=' + count.str() + ' failures=' + bad.str())
		}
	}
}
fn native_failure(log string) {
	assert log.contains('LINUX IOVOFFSET DETAIL: positioned write=0 v=0 libc=0 offset=4294967419 high=0 result=2/0 alias=4c,4f data=48,49 buffer=4c,4f position=5'), 'native failure markers required'
	assert log.contains('LINUX IOVOFFSET DETAIL: positioned write=1 v=0 libc=0 offset=4294967419 high=0 result=2/0 alias=58,59 data=48,49')
	assert log.contains('LINUX IOVOFFSET DETAIL: pipe sentinel write=0 v=0 high=4294967295 result=2/0 queued=0 buffer=41,42')
	assert log.contains('LINUX IOVOFFSET DETAIL: pipe sentinel write=1 v=1 high=0 result=-1/29 queued=0 buffer=00,00')
	assert !log.split_into_lines().any(it.contains('positioned') && it.contains('libc=1'))
	outcomes(log, false)
	assert log.contains('LINUX IOVOFFSET FAIL: native 64-bit offsets or v1/v2 negative offsets')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVOFFSET: PASS')
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
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovoffset-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required')
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 62
	for path, hash in inputs { if !path.starts_with('kernel/') || path == 'kernel/syscall/table/linux_compat.v' { assert digest(root + path) == hash } }
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '655 source files, 406 allocation sites', 'x86_64': '651 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == '26d595fa75eeadc9f37afdb4e1eed653434c3c09'
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_compat.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		decode := definition(generated, 'table__native_vector_offset')
		assert decode.contains('return (i64)(low);') && !decode.contains('_high') && !decode.contains('<<') && !decode.contains('&')
		for kind in ['preadv', 'pwritev'] {
			v1 := definition(generated, 'table__syscall_linux_' + kind)
			v2 := definition(generated, 'table__syscall_linux_' + kind + '2')
			assert v1.contains('table__native_vector_offset(pos_low, pos_high) < 0')
			refuse := v1.index('errno__einval') or { panic('missing v1 negative refusal') }
			delegate := v1.index('table__syscall_linux_' + kind + '2(') or { panic('missing v1 delegation') }; assert refuse < delegate
			assert v2.contains('table__native_vector_offset(pos_low, pos_high)') && v2.contains('offset < -1')
			v2_refuse := v2.index('errno__einval') or { panic('missing v2 negative refusal') }
			import_at := v2.index('table__validate_linux_iov(') or { panic('missing import') }; assert v2_refuse < import_at
			assert v2.contains('offset == -1') && v2.contains('table__syscall_linux_' + kind.all_after('p') + '(')
			assert !v1.contains('malloc(') && !v2.contains('malloc(') && !v2.contains('memdup(')
		}
		mut artifacts := map[string]string{}
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix; receipt := object(state + '/receipt.json')!
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == digest(state + '/kernel/bin/vinix')
			if phase == 'after' { assert receipt['kernel_sha256']!.str() == digest(tree + 'kernel/bin/vinix') }
			else { assert receipt['kernel_sha256']!.str() == object(out + 'iovrange-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()['after_kernel'] }
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 8 }
			mut names := []string{}
			for row in rows {
				item := row.as_map(); name := item['name']!.str(); names << name
				assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert item['source_sha256']!.str() == digest(state + '/sources/' + name + 'fixture/core.v')
				assert item['init_sha256']!.str() == digest(state + '/' + name + '/init') && item['iso_sha256']!.str() == digest(state + '/' + name + '/test.iso')
				if name == 'iovoffset' {
					fixture := os.read_file(state + '/' + name + '/fixture.c')!
					assert !fixture.contains('memdup(') && !fixture.contains('v_fixed_index') && !fixture.contains('malloc(')
					assert definition(fixture, 'iovoffsetfixture__storage').count('alloca(') == 2
					assert definition(fixture, 'iovoffsetfixture__positioned').count('alloca(') == 2
					assert definition(fixture, 'iovoffsetfixture__pipe_sentinel').contains('O_NONBLOCK')
				}
				artifacts[phase + '_' + name + '_generated_c'] = digest(state + '/' + name + '/fixture.c')
			}
			log := os.read_file(state + '.log')!; assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
			if phase == 'before' { assert names == ['iovoffset']; native_failure(log) }
			else {
				assert names == ['iovoffset', 'iovrange', 'pathio', 'open', 'readerror', 'pipezero', 'runtime', 'sharedmem']
				outcomes(log, true); assert !log.contains('LINUX IOVOFFSET FAIL') && !log.contains('LINUX IOVOFFSET DETAIL')
				for name in names { assert log.split_into_lines().any(it.trim_space() == 'LINUX ' + name.to_upper() + ': PASS') }
				for marker in ['IOVOFFSET', 'IOVRANGE'] { retention(log, arch, marker) }
			}
			label := 'iovoffset-' + phase + '-' + arch; publish(state + '/receipt.json', out + label + '.json')!; publish(state + '.log', out + label + '.log')!
			artifacts[phase + '_kernel'] = receipt['kernel_sha256']!.str(); artifacts[phase + '_receipt'] = digest(state + '/receipt.json'); artifacts[phase + '_log'] = digest(state + '.log')
		}
		assert artifacts['before_iovoffset_generated_c'] == artifacts['after_iovoffset_generated_c']
		artifacts['kernel_generated_c'] = digest(tree + 'kernel/obj/blob.c'); artifacts['compiler'] = digest('/tmp/vinix-seccomp-1012/v-snapshot/v')
		artifacts['controller'] = digest(area + 'run'); artifacts['audit'] = digest(@FILE)
		for label in ['host-tests', 'allocs-before', 'allocs-after'] { artifacts[label] = digest(area + label + '.log') }
		evidence := Evidence{arch, 'Native musl ELF64 root/UID1000: 696 positioned-vector cases preserve complete pos_l, ignore native pos_h, reject signed negatives before malformed vector/descriptor errors, and reserve current-position -1 behavior for v2. Sparse data at 4 GiB + 123, 8 GiB - 1 (crossing 8 GiB), 8 GiB + 17 and lower 32-bit aliases are verified by scalar I/O, file size/blocks and cursor. Each unchanged cohort fails 60 raw offset cases, 144 negative cases and 14 sentinel cases; public musl wrappers already pass and remain preservation controls. Fixed cohorts pass all 348 cases each. Two 200-cycle valid/error/sentinel cohorts retain flat slab classes/big pages (321 ARM, 4258 x86); native range regressions remain flat. Eight guest cases and eight host tests pass; 62 input hashes verified. Existing 406 ARM/295 x86 allocation allowance failures are unchanged. GNU libc wrappers, native ELF32/translation, positioned header/descriptor lifetime, positive-offset error ordering, flags, MAX_RW_COUNT, shared-offset atomicity, disk-backed files and exhaustion remain separate qualification', '26d595fa75eeadc9f37afdb4e1eed653434c3c09', artifacts, inputs}
		os.write_file(out + 'iovoffset-' + arch + '-evidence.json', json2.encode(evidence, prettify: true) + '\n')!
	}
	for label in ['host-tests', 'allocs-before', 'allocs-after'] { publish(area + label + '.log', out + 'iovoffset-' + label + '.log')! }
	println('Native full-width vector offsets, negative/sentinel errors, retention and unchanged allocation audit failures: verified')
}
