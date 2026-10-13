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
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX SEEKERROR OUTCOMES: ordinary=' + ordinary.str() + ' cases=3888 failures=' + if passing { '0' } else { '2268' })
		assert log.contains('LINUX SEEKERROR CONTROLS: ordinary=' + ordinary.str() + ' descriptors/aliases/metadata/cursors/bytes/queues/readiness PASS')
	}
}
fn native_failure(log string) {
	assert log.contains('LINUX SEEKERROR DETAIL: kind=2 offset=0 whence=5 result=-1/29 expected=-1/22'), 'native failure markers required'
	assert log.contains('LINUX SEEKERROR DETAIL: kind=5 offset=0 whence=5 result=-1/29 expected=-1/22')
	assert log.contains('LINUX SEEKERROR DETAIL: kind=8 offset=0 whence=5 result=-1/29 expected=-1/22')
	outcomes(log, false)
	assert log.contains('LINUX SEEKERROR FAIL: invalid selector precedence or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX SEEKERROR: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX SEEKERROR SLAB:') && !line.starts_with('LINUX SEEKERROR STORAGE:') { continue }
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
// Remove only the new early selector error. Existing FD/lock owners and all
// other kernel bodies must remain identical to baseline.
fn restore_generated(generated string, baseline string) {
	body := definition(generated, 'fs__syscall_seek')
	start := '\n\tif ((whence < 0) || (whence > 4)) {'
	assert body.count(start) == 1
	guard := start + body.all_after(start).all_before('\n\t}\n') + '\n\t}\n'
	assert guard.count('file__FD__unref(fd)') == 1 && guard.contains('errno__einval') && guard.contains('return _t3;')
	assert !guard.contains('klock__') && !guard.contains('malloc(') && !guard.contains('handle->loc')
	guard_position := body.index(start) or { panic('missing guard') }
	opath_position := body.index('handle->flags & resource__o_path') or { panic('missing O_PATH check') }
	policy_position := body.index('file__Handle__mac_check(') or { panic('missing policy check') }
	lock_position := body.index('klock__Lock__acquire(') or { panic('missing handle lock') }
	assert opath_position < guard_position && guard_position < policy_position && guard_position < lock_position
	before := definition(baseline, 'fs__syscall_seek')
	assert canonical_returns(body.replace(guard, '\n')) == canonical_returns(before)
	assert generated.replace(body, before) == baseline, 'only the seek selector guard and return temporaries may change generated C'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-seekselector-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '6e27e8ee3cd060e4a75376a4f71e620500126304'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	changed := ['kernel/fs/vfs.v']
	for path in changed { assert digest(root + path) == inputs[path] }
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert digest(area + 'host-tests.log') == sha256.sum(os.read_bytes(area + 'host-tests.log')!).hex()
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
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else if arch == 'aarch64' { 5 } else { 2 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				interrupted := phase == 'after' && arch == 'aarch64' && name == 'runtime'
				assert entry['exit_code']!.int() == if phase == 'before' || interrupted { 1 } else { 0 }
				if interrupted { assert entry['detail']!.str().starts_with('cp: failed to write to ') && entry['detail']!.str().ends_with('/runtime/efivars.fd') }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'seekerror' {
					assert digest(c) == digest(area + 'preview.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true); retention(log, arch) }
				}
				if phase == 'after' && !interrupted { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == if arch == 'aarch64' { ['seekerror', 'scalarabi', 'opathseek', 'pathio', 'runtime'] } else { ['seekerror', 'scalarabi'] }
				assert !log.contains('Linux compatibility guest suite: PASS') && !log.contains('LINUX RUNTIME: PASS')
				if arch == 'aarch64' { assert log.contains('Linux compatibility qualification failed') }
				else { assert !log.contains('LINUX OPATHSEEK: PASS') }
			}
			else { assert names == ['seekerror'] }
			publish(state + 'receipt.json', out + 'seekerror-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'seekerror-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_seekerror_generated_c'] == artifacts['after_seekerror_generated_c']
		state := area + 'completion-' + suffix + '/'; completion := object(state + 'receipt.json')!
		assert completion['architecture']!.str() == arch && completion['kernel_sha256']!.str() == artifacts['after_kernel'] && digest(state + 'kernel/bin/vinix') == artifacts['after_kernel']
		mut completed := []string{}
		completion_log := os.read_file(area + 'completion-' + suffix + '.log')!
		for row in completion['results']!.as_array() {
			entry := row.as_map(); name := entry['name']!.str(); assert name !in completed; completed << name
			assert entry['exit_code']!.int() == 0
			assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
			assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
			original_c := area + 'after-' + suffix + '/' + name + '/fixture.c'
			if os.exists(original_c) {
				assert digest(state + name + '/fixture.c') == digest(original_c)
				artifacts['interrupted_' + name + '_generated_c'] = digest(original_c)
			} else {
				// The interrupted x86 controller never compiled these later cases.
				// Bind their C to the already published scalar-ABI qualification.
				assert arch == 'x86_64' && name in ['pathio', 'runtime']
				earlier := root + 'tests/linux-compat/results/2026-10-13/scalarabi-x86_64-evidence.json'
				assert digest(state + name + '/fixture.c') == object(earlier)!['artifacts']!.as_map_of_strings()['after_' + name + '_generated_c']
				artifacts['earlier_scalarabi_evidence'] = digest(earlier)
			}
			assert completion_log.contains('LINUX ' + name.to_upper() + ': PASS')
			artifacts['completion_' + name + '_generated_c'] = digest(state + name + '/fixture.c')
		}
		assert completed == if arch == 'aarch64' { ['runtime'] } else { ['opathseek', 'pathio', 'runtime'] }
		assert completion_log.contains('Linux compatibility guest suite: PASS')
		artifacts['completion_receipt'] = digest(state + 'receipt.json'); artifacts['completion_log'] = digest(area + 'completion-' + suffix + '.log')
		publish(state + 'receipt.json', out + 'seekerror-completion-' + arch + '.json')!; publish(area + 'completion-' + suffix + '.log', out + 'seekerror-completion-' + arch + '.log')!
		context := 'Native musl ELF64 lseek selector errors:3888 checks per root/UID1000 cohort cover twelve descriptor classes, original/dup/F_DUPFD_CLOEXEC handles, three upper FD/selector patterns, four signed64 offsets and three invalid low32 selectors. Ordinary files/directories, both anonymous pipe ends, named FIFO, UNIX stream/datagram/seqpacket and /dev/null return EINVAL for selectors above4; invalid and O_PATH file/FIFO descriptors retain EBADF first. Fresh unchanged kernels fail2268 checks per cohort; candidates pass7776 per architecture. Valid0..4 stream refusals and file/directory cursor controls, sparse ordinary seeks, metadata/alias flags and real queued bytes/FIONREAD/poll/EAGAIN remain valid. Sixteen stable descriptors warm32 and measure200 cycles of1296 invalid seeks, valid controls and three transient dup/seek/close operations; slab live objects and big pages remain flat in both cohorts. Only a two-line guard in fs/vfs.v changes at6e27e8ee3. Generated C unrefs the FD exactly once before policy/lock/type checks; removing the guard and canonicalizing return temporaries restores the complete seek body, and replacing only that body restores the entire baseline kernel C. No other consuming body or owner changes. All four actual fixture C captures match preview; the handle table and two observer snapshots use bounded alloca, without hidden heap promotion. Independent final lifetime review is closed. Both architectures also pass scalarabi, opathseek, pathio and runtime; eight host test files, fresh builds and inventory checks pass. Existing allocation allowance failures retain406ARM/295x86 sites and identical NEW rows. All63 isolated semantic source inputs are fingerprinted separately from the public committed-parent inventory. Both failing audit controls execute. This does not qualify regular SEEK_DATA/SEEK_HOLE, valid character-device seek semantics, relative/end overflow, shared-offset races, GNU/foreign/ELF32 paths, allocator exhaustion, disk-backed files or complete installation/sandbox/portal/runtime compatibility.'
		recovery := ' Original candidate aggregates remain unsuccessful: host disk exhaustion refused the ARM runtime EFI-vars copy after four successful cases and left the x86 log truncated with two successful receipt rows. Fresh completion suites rerun ARM runtime and x86 opathseek/pathio/runtime on identical kernels and fixture C. Interrupted aggregates are not relabeled passing.'
		os.write_file(out + 'seekerror-' + arch + '-evidence.json', json2.encode(Evidence{arch, context + recovery, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'seekerror-' + name + '.log')! }
	println('Seek error precedence qualification audit: PASS')
}
