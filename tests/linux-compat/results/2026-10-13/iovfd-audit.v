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
		assert log.contains('LINUX IOVFD OUTCOMES: ordinary=' + ordinary.str() + ' cases=3080 failures=' + if passing { '0' } else { '1144' })
	}
}
fn native_failure(log string) {
	assert log.contains('kind=0 write=0 version=0 high=4294967296 variant=0 count=0 result=-1/9 expected=0/0'), 'native failure markers required'
	assert log.contains('kind=0 write=0 version=0 high=4294967296 variant=8 count=2 result=-1/9 expected=2/0')
	assert log.contains('kind=0 write=0 version=1 high=4294967296 variant=3 count=1 result=-1/9 expected=-1/14')
	assert log.contains('kind=0 write=0 version=2 high=4294967296 variant=10 count=4294967297 result=-1/9 expected=-1/22')
	assert log.contains('kind=4 write=0 version=1 high=4294967296 variant=0 count=0 result=-1/9 expected=-1/29')
	assert !log.split_into_lines().any(it.contains('DETAIL:') && it.contains(' high=0 '))
	assert !log.split_into_lines().any(it.contains('DETAIL:') && it.contains(' variant=9 ') && !it.contains(' version=0 '))
	outcomes(log, false)
	assert log.contains('LINUX IOVFD FAIL: native vector descriptor width or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVFD: PASS')
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
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovfd-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required')
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'ad4c6f638d04ae77ea8bcc0b1db755ee32323d83'
	inputs := object(root + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 62
	for path, hash in inputs { assert digest(root + path) == hash }
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
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
			'kernel/syscall/table/linux_common.v', 'kernel/syscall/table/linux_compat.v']
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!
		baseline_c := os.read_file(area + 'before-' + suffix + '.c')!
		for name in ['table__linux_positioned_iov', 'table__linux_readv_flags', 'table__linux_writev_flags'] {
			body := definition(generated, name); before_body := definition(baseline_c, name)
			lookup := 'file__fd_from_fdnum(NULL, fdnum)'
			narrow := 'file__fd_from_fdnum(NULL, (i64)((u32)(fdnum)))'
			assert before_body.count(lookup) == 1
			assert body == before_body.replace(lookup, narrow)
			assert body.count('table__import_linux_iov(') == 1 && body.contains('vinix_stack_alloc(')
			assert body.contains('table__LinuxIOVector__release(') && body.contains('file__FD__unref(')
		}
		for name in ['readv', 'writev', 'preadv', 'pwritev', 'preadv2', 'pwritev2'] {
			assert definition(generated, 'table__syscall_linux_' + name) == definition(baseline_c, 'table__syscall_linux_' + name)
		}
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host-tests': digest(area + 'host-tests.log'), 'geometry': digest(area + 'geometry.log'),
			'allocs-before': digest(area + 'allocs-before.log'), 'allocs-after': digest(area + 'allocs-after.log'), 'previous_native_evidence': digest(out + 'iovflags-' + arch + '-evidence.json')}
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix + '/'
			receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash
			assert digest(state + 'kernel/bin/vinix') == kernel_hash
			log := os.read_file(area + phase + '-' + suffix + '.log')!
			if phase == 'before' {
				prior := object(out + 'iovflags-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()
				assert kernel_hash == prior['after_kernel'] && digest(area + 'before-' + suffix + '.c') == prior['kernel_generated_c']
			}
			artifacts[phase + '_kernel'] = kernel_hash
			artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(area + phase + '-' + suffix + '.log')
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 5 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v')
				assert entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'iovfd' {
					fixture := os.read_file(c)!
					assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('ioctl(') && fixture.contains('pread(') && fixture.contains('pwrite(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true); retention(log, arch, 'IOVFD') }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == ['iovfd', 'iovflags', 'iovposition', 'iovpin', 'runtime']
				for marker in ['IOVFLAGS', 'IOVPOSITION', 'IOVPIN'] { retention(log, arch, marker) }
			}
			publish(state + 'receipt.json', out + 'iovfd-' + phase + '-' + arch + '.json')!
			publish(area + phase + '-' + suffix + '.log', out + 'iovfd-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_iovfd_generated_c'] == artifacts['after_iovfd_generated_c']
		context := 'Native musl ELF64 root/UID1000 descriptor-width conformance: 3080 checks per cohort across readv/writev, v1/v2 explicit positions and v2 current positions. Five upper-word patterns preserve low32 descriptor identity, actual data/cursors and earlier descriptor/access/seek/import/negative-offset errors; full-width vector counts remain invalid. Unchanged controls fail 1144 checks per cohort while ordinary descriptors and negative positioned offsets already pass. Fixed cohorts pass all 6160 checks per architecture and two 200-cycle imports retain flat slab/big-page storage. The only emitted-C consumer change is the unsigned32 descriptor cast; all six syscall wrappers and existing ownership remain identical. Baseline kernels/C are reused from the preceding flags receipts and bound to those exact hashes. Five guest regressions and eight host tests pass; existing 406ARM/295x86 allocation allowance failures remain unchanged. This covers these native vector descriptors; scalar and other FD APIs, GNU/foreign ABIs, deterministic positioned races, shared-offset atomicity, allocator exhaustion and full Linux application qualification remain separate.'
		os.write_file(out + 'iovfd-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'geometry', 'allocs-before', 'allocs-after'] { publish(area + name + '.log', out + 'iovfd-' + name + '.log')! }
	println('Vector-descriptor qualification audit: PASS')
}
