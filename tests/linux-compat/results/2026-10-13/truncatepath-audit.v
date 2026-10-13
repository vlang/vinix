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
	lines := source.split_into_lines().filter(!it.starts_with('\t') && !it.starts_with(' ') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1, name + ': ' + lines.join('\n'); return source.all_after(lines[0]).all_before('\n}\n')
}
fn canonical_returns(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if (token.starts_with('_t') && token.len > 2 && token[2..].bytes().all(it.is_digit())) || (token.starts_with('__discard_') && token.len > 10 && token[10..].bytes().all(it.is_digit() || it == `_`)) {
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
	assert arch in ['aarch64', 'x86_64']
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX TRUNCATEPATH OUTCOMES: ordinary=' + ordinary.str() + ' cases=384 failures=' + if passing { '0' } else { '144' })
		if passing { assert log.contains('LINUX TRUNCATEPATH CONTROLS: ordinary=' + ordinary.str() + ' symlink-targets/shrink/grow/zero-fill/metadata/blocks/flags/aliases/cursors/private/queued-bytes/readiness PASS') }
	}
}
fn native_failure(log string, arch string) {
	assert log.contains('kind=6 raw=1 length=0 result=0/0 expected=-1/22 size=0/0'), 'native failure markers required'
	assert log.contains('kind=4 raw=1 length=0 result=-1/2 expected=-1/22 size=0/0')
	assert log.contains('kind=22 raw=1 length=0 result=-1/2 expected=-1/22 size=0/0')
	outcomes(log, false, arch)
	mut remaining := log
	for ordinary in [1, 0] {
		marker := 'LINUX TRUNCATEPATH OUTCOMES: ordinary=' + ordinary.str()
		cohort := remaining.all_before(marker); remaining = remaining.all_after(marker)
		details := cohort.split_into_lines().filter(it.starts_with('LINUX TRUNCATEPATH DETAIL:'))
		assert details.len == 144 && details.all(it.contains('expected=-1/22') && !it.contains('length=-'))
		assert details.filter(it.contains('result=0/0')).len == 72
		assert details.filter(it.contains('result=-1/2')).len == if ordinary == 1 { 48 } else { 72 }
		assert details.filter(it.contains('result=-1/13')).len == if ordinary == 1 { 24 } else { 0 }
	}
	assert log.contains('LINUX TRUNCATEPATH FAIL: pathname type errors or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX TRUNCATEPATH: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX TRUNCATEPATH SLAB:') && !line.starts_with('LINUX TRUNCATEPATH STORAGE:') { continue }
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
	name := 'fs__syscall_truncate'; body := definition(generated, name); old := definition(baseline, name)
	policy := '\tif (!fs__policy_check(node, proc__policy_write)) {'
	assert body.all_before('\tu32 mode = ') == old.all_before(policy)
	assert body.contains('u32 mode = ') && body.all_before('u32 mode = ').contains('fs__get_node(')
	for condition, code in {'if (stat__isdir(mode)) {': 'errno__eisdir', 'if (!stat__isreg(mode)) {': 'errno__einval'} {
		assert body.count(condition) == 1
		branch := body.all_after(condition).all_before('\n\t}\n')
		assert branch.contains(code) && branch.count('string__free(&path);') == 1
		assert !branch.contains('fs__policy_check(') && !branch.contains('grow(') && !branch.contains('resource_to_change(')
	}
	assert body.all_before('if (!stat__isreg(mode))').len < body.all_before(policy).len
	lines := old.split_into_lines().filter(it.starts_with('\tif (stat__isdir(') && it.ends_with(' {')); assert lines.len == 1
	directory := lines[0] + old.all_after(lines[0]).all_before('\n\t}\n') + '\n\t}\n'
	assert old.count(directory) == 1
	assert canonical_returns(body.all_after(policy)) == canonical_returns(old.replace(directory, '').all_after(policy))
	assert !body.contains('malloc(') && !body.contains('memdup(') && !body.contains('new_array') && !body.contains('klock__')
	assert generated.count(body) == 1 && generated.replace(body, old) == baseline, 'only pathname truncate eligibility may change the entire generated kernel'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!, 'aarch64'); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-truncatepath-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'dd2c181c1be8fa049a632811f3cf5c60f99f1e68'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	changed := ['kernel/fs/vfs.v']; assert digest(root + changed[0]) == inputs[changed[0]]
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	for suffix in ['arm', 'x86'] {
		assert os.read_file(area + 'build-after-' + suffix + '.log')!.contains('No space left on device')
		good := os.read_file(area + 'build-after-final-' + suffix + '.log')!
		assert good.contains('-o bin/vinix') && !good.contains('Error ')
	}
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
		// Preserve the original unseeded native failures and isolate the fixture change.
		original := area + 'before-' + suffix + '/'; original_receipt := object(original + 'receipt.json')!
		assert original_receipt['architecture']!.str() == arch && original_receipt['kernel_sha256']!.str() == digest(area + 'before-' + suffix + '.kernel')
		original_rows := original_receipt['results']!.as_array(); assert original_rows.len == 1
		original_entry := original_rows[0].as_map(); assert original_entry['name']!.str() == 'truncatepath' && original_entry['exit_code']!.int() == 1
		assert original_entry['source_sha256']!.str() == digest(original + 'sources/truncatepathfixture/core.v')
		assert original_entry['init_sha256']!.str() == digest(original + 'truncatepath/init') && original_entry['iso_sha256']!.str() == digest(original + 'truncatepath/test.iso')
		assert digest(original + 'truncatepath/fixture.c') == digest(area + 'preview.c')
		original_log := os.read_file(original.trim_right('/') + '.log')!
		assert original_log.contains('LINUX TRUNCATEPATH OUTCOMES: ordinary=1 cases=384 failures=121') && original_log.contains('LINUX TRUNCATEPATH OUTCOMES: ordinary=0 cases=384 failures=96')
		assert original_log.contains('LINUX TRUNCATEPATH FAIL: pathname type errors or storage') && !original_log.split_into_lines().any(it.trim_space() == 'LINUX TRUNCATEPATH: PASS')
		old_seed := '\t\te := C.__errno_location(); *e = 0\n'
		new_seed := '\t\t// Failed resource hooks must not borrow a previous kernel errno.\n\t\te := C.__errno_location(); *e = 0; seed := C.open(pathname(18), C.O_RDONLY)\n\t\tif seed >= 0 { C.close(seed); return false }; if *e != C.ENOENT { return false }; *e = 0\n'
		final_source := os.read_file(root + 'tests/linux-compat/truncatepathfixture/core.v')!
		assert final_source.count(new_seed) == 1 && final_source.replace(new_seed, old_seed) == os.read_file(original + 'sources/truncatepathfixture/core.v')!
		initial_c := os.read_file(original + 'truncatepath/fixture.c')!; final_c := os.read_file(area + 'final-preview.c')!
		for name in ['pathname', 'restore', 'cleanup', 'setup', 'queues', 'private_permissions', 'storage_cycle', 'snapshot', 'storage', 'qualify', 'run'] {
			function := 'truncatepathfixture__' + name
			assert canonical_returns(definition(initial_c, function)) == canonical_returns(definition(final_c, function))
		}
		artifacts['original_receipt'] = digest(original + 'receipt.json'); artifacts['original_log'] = digest(original.trim_right('/') + '.log')
		artifacts['original_fixture_c'] = digest(original + 'truncatepath/fixture.c')
		publish(original + 'receipt.json', out + 'truncatepath-original-before-' + arch + '.json')!
		publish(original.trim_right('/') + '.log', out + 'truncatepath-original-before-' + arch + '.log')!
		artifacts['build_host_failure'] = digest(area + 'build-after-' + suffix + '.log')
		artifacts['build_retry'] = digest(area + 'build-after-final-' + suffix + '.log')
		mut qualified := []string{}
		for phase in ['before', 'after'] {
			state := area + if phase == 'before' { 'before-final-' } else { 'after-' } + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else if arch == 'aarch64' { 4 } else { 3 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'truncatepath' {
					assert digest(c) == digest(area + 'final-preview.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log, arch) } else { outcomes(log, true, arch); retention(log, arch) }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == if arch == 'aarch64' { ['truncatepath', 'truncateabi', 'seekextent', 'sharedmem'] } else { ['truncatepath', 'truncateabi', 'seekextent'] }
				assert !log.contains('Linux compatibility guest suite: PASS'); qualified << names
			}
			else { assert names == ['truncatepath'] }
			publish(state + 'receipt.json', out + 'truncatepath-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'truncatepath-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_truncatepath_generated_c'] == artifacts['after_truncatepath_generated_c']
		// Fresh completions qualify only the missing cases, on the identical kernel.
		completion := area + 'completion-success-' + suffix + '/'; completion_receipt := object(completion + 'receipt.json')!
		assert completion_receipt['architecture']!.str() == arch && completion_receipt['kernel_sha256']!.str() == artifacts['after_kernel']
		assert digest(completion + 'kernel/bin/vinix') == artifacts['after_kernel']
		completion_log := os.read_file(completion.trim_right('/') + '.log')!; assert completion_log.contains('Linux compatibility guest suite: PASS')
		completion_rows := completion_receipt['results']!.as_array(); assert completion_rows.len == if arch == 'aarch64' { 1 } else { 2 }
		mut completion_names := []string{}
		for row in completion_rows {
			item := row.as_map(); name := item['name']!.str(); assert name !in qualified && name !in completion_names; completion_names << name
			assert item['exit_code']!.int() == 0 && completion_log.contains('LINUX ' + name.to_upper() + ': PASS')
			assert item['source_sha256']!.str() == digest(completion + 'sources/' + name + 'fixture/core.v') && item['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
			assert item['init_sha256']!.str() == digest(completion + name + '/init') && item['iso_sha256']!.str() == digest(completion + name + '/test.iso')
			artifacts['completion_' + name + '_c'] = digest(completion + name + '/fixture.c')
			partial_c := area + 'after-' + suffix + '/' + name + '/fixture.c'
			if os.exists(partial_c) { assert digest(partial_c) == artifacts['completion_' + name + '_c']; artifacts['partial_' + name + '_c'] = digest(partial_c) }
		}
		assert completion_names == if arch == 'aarch64' { ['runtime'] } else { ['sharedmem', 'runtime'] }
		qualified << completion_names; assert qualified == ['truncatepath', 'truncateabi', 'seekextent', 'sharedmem', 'runtime']
		artifacts['completion_receipt'] = digest(completion + 'receipt.json'); artifacts['completion_log'] = digest(completion.trim_right('/') + '.log')
		publish(completion + 'receipt.json', out + 'truncatepath-completion-' + arch + '.json')!
		publish(completion.trim_right('/') + '.log', out + 'truncatepath-completion-' + arch + '.log')!
		if arch == 'aarch64' {
			failed := area + 'completion-arm/'; failed_receipt := object(failed + 'receipt.json')!
			assert failed_receipt['architecture']!.str() == arch && failed_receipt['kernel_sha256']!.str() == artifacts['after_kernel']
			failed_rows := failed_receipt['results']!.as_array(); assert failed_rows.len == 1
			failed_item := failed_rows[0].as_map(); assert failed_item['name']!.str() == 'runtime' && failed_item['exit_code']!.int() == 1 && failed_item['iso_sha256']!.str() == ''
			assert failed_item['source_sha256']!.str() == digest(failed + 'sources/runtimefixture/core.v') && failed_item['init_sha256']!.str() == digest(failed + 'runtime/init')
			assert digest(failed + 'runtime/fixture.c') == artifacts['completion_runtime_c'] && digest(failed + 'runtime/init') == digest(completion + 'runtime/init')
			failed_log := os.read_file(area + 'completion-arm.log')!; assert failed_log.contains('No space left on device') && !failed_log.contains('LINUX RUNTIME: PASS')
			artifacts['failed_completion_receipt'] = digest(failed + 'receipt.json'); artifacts['failed_completion_log'] = digest(area + 'completion-arm.log')
			publish(failed + 'receipt.json', out + 'truncatepath-failed-completion-aarch64.json')!; publish(area + 'completion-arm.log', out + 'truncatepath-failed-completion-aarch64.log')!
		}
		context := 'Native musl ELF64 pathname truncate:384 raw/libc checks per root/UID1000 cohort cover24 path classes, direct/relative-absolute symlink targets and eight signed64 lengths. Negative EINVAL precedes lookup faults; resolved directories return EISDIR and all other nonregular targets EINVAL before policy/attributes/copy-up/grow. Valid regular paths actually shrink/grow with preserved prefixes and zero-filled tails; private files retain EACCES. Inode/device/type/UID/GID/size/blocks and FD flags/shared cursors remain correct; real public/private FIFO and UNIX datagram AB/readiness survives calls and is drained/replenished between sequential children. Ten stable inherited descriptors plus transient aliases survive32 warmups and200 measured cycles of88 raw calls plus3 dup/metadata/close controls; loops/inaccessible pointers are outcome checks outside that measured loop. All slab classes and big pages stay flat. Original unseeded baselines ordinary121/root96 remain failed; their passing FIFO errors borrowed prior errno. Only a controlled failed-open ENOENT seed was added to the probe, with unexpected successful seed FDs closed, before fresh final baseline/candidate captures. Corrected baseline144 failures/cohort:72device false successes,72root or48ordinary staleENOENT stream refusals and24ordinary privateFIFO EACCES errors. Candidates pass768 per architecture. Both first candidate builds fail on host ENOSPC dependency writes; preserved original logs and unchanged-source successful retries are pinned. Current C/kernel/init/source/log/receipts retained; only audited older images/build objects retired and older C losslessly compressed with verified restoration hashes. Only fs/vfs.v differs atdd2c181c1. New type errors free the existing path once; negative/copy/lookup prefix and policy/attr/access/copy-up/grow tail are unchanged apart from moving the directory check. Replacing that body restores the entire baseline generated kernel C. Actual final before/after fixture C matches preview without hidden allocation/promotion; all ownership/checking functions outside the scalar seed remain identical after canonicalizing generated return/unused-loop names. Independent final lifetime/capture/retention review closes;75/75ARM198/198x86 pages stay flat. Initial aggregates stop during CLI continuation after4ARM/3x86 recorded successes; fresh successful completions cover only missing cases on identical kernel/C. FirstARMcompletion hits host ENOSPC image staging, with real init hash and blank image hash; its failed log/receipt is preserved separately. Both candidates also pass truncateabi/seekextent/sharedmem/runtime. Eight host tests, both kernel builds and inventory checks pass; existing allocation allowances retain406ARM/295x86 sites and identical NEW rows. All63 isolated inputs pinned separately from public committed-parent inventory; both failing audit controls execute. Limits:disk/readonly mounts/overlays, timestamps/privilege-bit clearing/protected attributes and restrictive policy combinations, huge sparse growth/concurrent truncation, allocator exhaustion, GNU/foreign/ELF32 and complete application installation/sandbox/portal/runtime compatibility remain separate.'
		os.write_file(out + 'truncatepath-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'truncatepath-' + name + '.log')! }
	for suffix in ['arm', 'x86'] { for phase in ['build-after-', 'build-after-final-'] { publish(area + phase + suffix + '.log', out + 'truncatepath-' + phase + suffix + '.log')! } }
	println('Pathname truncate qualification audit: PASS')
}
