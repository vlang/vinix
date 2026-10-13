// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os
import strings

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

struct Evidence {
	architecture string
	context string
	base_commit string
	artifacts map[string]string
	source_inputs map[string]string
}
fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }; defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}; defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; panic(err) }
			if n == 0 { break }; assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}; assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; panic(err) }
			if n == 0 { break }; assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}; state.checksum_into(mut result); return result.hex()
	}
}
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) { assert os.read_bytes(output)! == data } else { os.write_file_array(output, data)! }
}
fn git(tree string, args []string) !string {
	mut command := ['-C', tree]; command << args
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0, output; return output.trim_space()
}
fn definition(source string, name string) string {
	lines := source.split_into_lines().filter(it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn canonical_returns(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if token.starts_with('_t') && token.len > 2 && token[2..].bytes().all(it.is_digit()) {
				if token !in names { names[token] = '_return' + names.len.str() }
				output.write_string(names[token])
			} else { output.write_string(token) }
		} else { output.write_u8(source[position]); position++ }
	}
	return output.str()
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn outcomes(log string, passing bool, arch string) {
	for ordinary in 0 .. 2 {
		failures := if passing { 0 } else if arch == 'aarch64' && ordinary == 1 { 504 } else { 432 }
		assert log.contains('LINUX TRUNCATEACCESS OUTCOMES: ordinary=' + ordinary.str() + ' cases=928 failures=' + failures.str())
		if passing { assert log.contains('LINUX TRUNCATEACCESS CONTROLS: ordinary=' + ordinary.str() + ' shrink/grow/zero-fill/cursors/metadata/flags/private/queues/readiness PASS') }
	}
}
fn native_failure(log string, arch string) {
	assert log.contains('kind=4 alias=0 raw=1 length=0 result=0/0 expected=-1/9 size=4/0'), 'native failure markers required'
	assert log.contains('kind=6 alias=0 raw=1 length=0 result=-1/21 expected=-1/22')
	assert log.contains('kind=11 alias=0 raw=1 length=0 result=0/0 expected=-1/22')
	outcomes(log, false, arch)
	mut remaining := log
	for ordinary in [1, 0] {
		marker := 'LINUX TRUNCATEACCESS OUTCOMES: ordinary=' + ordinary.str()
		cohort := remaining.all_before(marker); remaining = remaining.all_after(marker)
		details := cohort.split_into_lines().filter(it.starts_with('LINUX TRUNCATEACCESS DETAIL:'))
		assert details.len == if arch == 'aarch64' && ordinary == 1 { 504 } else { 432 }
		// The additional ARM ordinary-user failures are MAC-before-type errors.
		for kind in [9, 10] {
			rows := details.filter(it.contains('DETAIL: kind=' + kind.str() + ' '))
			assert rows.len == if arch == 'aarch64' && ordinary == 1 { 36 } else { 0 }
			assert rows.all(it.contains('result=-1/13 expected=-1/22'))
		}
		assert !details.any(it.contains('DETAIL: kind=1 ') || it.contains('DETAIL: kind=2 '))
	}
	assert log.contains('LINUX TRUNCATEACCESS FAIL: descriptor eligibility or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX TRUNCATEACCESS: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX TRUNCATEACCESS SLAB:') && !line.starts_with('LINUX TRUNCATEACCESS STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7
		group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0].u64() == pair[1].u64()
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'
			seen[key] = true; rows[group]++
		} else {
			assert fields[4] == 'cycles=200' && fields[6] == 'PASS'
			assert pair[0].u64() == if arch == 'aarch64' { u64(75) } else { u64(198) }; pages[group]++
		}
	}
	for group in 0 .. 2 { assert rows[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn restore_generated(generated string, baseline string) {
	name := 'file__syscall_ftruncate'; body := definition(generated, name); old := definition(baseline, name)
	handle := '\tfile__Handle* handle = fd->handle;'
	assert body.all_before(handle) == old.all_before(handle)
	assert body.contains('if (length < 0)') && body.all_before('if (length < 0)').len < body.all_before('file__fd_from_fdnum(').len
	path := body.all_after('if ((handle->flags & resource__o_path) != 0) {').all_before('\n\t}\n')
	assert path.contains('errno__ebadf') && path.count('file__FD__unref(fd);') == 1
	assert !path.contains('mac_check(') && !path.contains('grow(') && !path.contains('klock__')
	assert body.contains('resource__Resource* res = handle->resource;') && body.contains('i64 v_access = handle->flags & resource__o_accmode;')
	assert body.contains('if (!stat__isreg(') && body.contains('((v_access != resource__o_wronly) && (v_access != resource__o_rdwr))')
	eligibility := body.all_after('if (!stat__isreg(').all_before('\n\t}\n')
	assert eligibility.contains('errno__einval') && eligibility.count('file__FD__unref(fd);') == 1
	assert body.all_before('v_access != resource__o_rdwr').len < body.all_before('file__Handle__mac_check(').len
	assert canonical_returns(body.all_after('if (resource__is_protected(res))')) == canonical_returns(old.all_after('if (resource__is_protected(res))'))
	assert !body.contains('malloc(') && !body.contains('memdup(') && !body.contains('new_array') && !body.contains('klock__')
	assert generated.count(body) == 1 && generated.replace(body, old) == baseline, 'only ftruncate eligibility may change the whole generated kernel'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!, 'aarch64'); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-truncateaccess-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '538d93af8085bf773b2cba2bf4b0f71bdf7fc02e'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	changed := ['kernel/file/file.v']; assert digest(root + changed[0]) == inputs[changed[0]]
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == changed
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log')}
		// Preserve the strict-C compile rejection; it contains no runnable init/image.
		rejected := area + 'before-' + suffix + '/'; reject_receipt := object(rejected + 'receipt.json')!
		assert reject_receipt['architecture']!.str() == arch && reject_receipt['kernel_sha256']!.str() == digest(area + 'before-' + suffix + '.kernel')
		reject_rows := reject_receipt['results']!.as_array(); assert reject_rows.len == 1
		reject := reject_rows[0].as_map(); assert reject['name']!.str() == 'truncateaccess' && reject['exit_code']!.int() == 1
		assert reject['init_sha256']!.str() == '' && reject['iso_sha256']!.str() == ''
		assert reject['source_sha256']!.str() == digest(rejected + 'sources/truncateaccessfixture/core.v')
		assert digest(rejected + 'truncateaccess/fixture.c') == digest(area + 'preview.c')
		reject_log := os.read_file(rejected.trim_right('/') + '.log')!
		assert reject_log.contains('v_fixed_index') && reject_log.contains('pointer-sign') && !reject_log.contains('LINUX TRUNCATEACCESS OUTCOMES:')
		artifacts['rejected_receipt'] = digest(rejected + 'receipt.json'); artifacts['rejected_log'] = digest(rejected.trim_right('/') + '.log')
		artifacts['rejected_fixture_c'] = digest(rejected + 'truncateaccess/fixture.c')
		publish(rejected + 'receipt.json', out + 'truncateaccess-rejected-' + arch + '.json')!
		publish(rejected.trim_right('/') + '.log', out + 'truncateaccess-rejected-' + arch + '.log')!
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before-final-' } else { 'after-' } + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 5 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'truncateaccess' {
					assert digest(c) == digest(area + 'final-preview.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log, arch) } else { outcomes(log, true, arch); retention(log, arch) }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' { assert names == ['truncateaccess', 'pathio', 'sharedmem', 'seekextent', 'runtime']; assert log.contains('Linux compatibility guest suite: PASS') }
			else { assert names == ['truncateaccess'] }
			publish(state + 'receipt.json', out + 'truncateaccess-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'truncateaccess-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_truncateaccess_generated_c'] == artifacts['after_truncateaccess_generated_c']
		context := 'Native musl ELF64 ftruncate eligibility:928 raw/libc checks per root/UID1000 cohort cover20 descriptor classes, original/dup/F_DUPFD_CLOEXEC aliases and eight signed64 lengths. Negative lengths return EINVAL before lookup; O_PATH returns EBADF before policy/type; only WRONLY/RDWR regular files resize, with nonregular/readonly/mode3 returning EINVAL before MAC. Baseline ARM ordinary fails504/root432; x86 both432. The additional72 ARM ordinary failures are36 pipe and36 socket MAC-before-type errors; eligible regular resize probes pass all baselines. Candidates pass1856 per architecture, retain inode/device/type/UID/GID/size/FD flags, zero-filled resize bytes, shared cursors, private-open restrictions and actual pipe/socket/FIFO AB/readiness. Sixty stable cohort FDs plus temporary aliases survive32 warm-ups and200 measured cycles of80 probes plus3 duplicate controls; all slab classes and big pages remain flat:75ARM/198x86. Only file/file.v differs at538d93af808. Negative/pin prefix and protected/grow tail remain identical; replacing the ftruncate body restores the entire baseline generated C. No new allocation/lock/reference owner. All actual before/after fixture C equals final preview without hidden allocation/promotion. Initial strict-C failures from unavailable bounds helper and pointer-sign errors are preserved with blank init/image hashes. Independent final lifetime/retention review closes. Both candidates additionally pass pathio/sharedmem/seekextent/runtime. Eight host test files, both builds and inventory checks pass; allocation allowance failures retain406ARM/295x86 sites and identical NEW rows. All63 isolated source inputs are pinned separately from public committed-parent inventory; both failing audit controls execute. Limits:upper descriptor words, GNU/foreign/ELF32 paths, protected attributes/privilege-bit clearing, readonly mounts/disk, concurrent close/truncate, huge growth/allocation exhaustion and full installation/sandbox/portal/runtime qualification remain separate.'
		os.write_file(out + 'truncateaccess-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'truncateaccess-' + name + '.log')! }
	println('Native ftruncate eligibility qualification audit: PASS')
}
