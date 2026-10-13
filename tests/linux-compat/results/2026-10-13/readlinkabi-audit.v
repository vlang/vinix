// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os
import strconv
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
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('	') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
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
fn case_count(arch string) int { assert arch in ['aarch64', 'x86_64']; return if arch == 'aarch64' { 2160 } else { 2880 } }
fn failures(arch string, ordinary int, phase string) int {
	return if arch == 'aarch64' {
		if phase == 'before' { if ordinary == 1 { 814 } else { 820 } }
		else if phase == 'after' { 105 }
		else if phase == 'before-final' { if ordinary == 1 { 730 } else { 736 } }
		else if phase == 'after-final' { 21 }
		else if phase == 'before-corrected' { if ordinary == 1 { 712 } else { 718 } }
		else { 0 }
	} else {
		if phase == 'before' { if ordinary == 1 { 1088 } else { 1096 } }
		else if phase == 'after' { 112 }
		else if phase == 'before-final' { if ordinary == 1 { 1004 } else { 1012 } }
		else if phase == 'after-final' { 28 }
		else if phase == 'before-corrected' { if ordinary == 1 { 980 } else { 988 } }
		else { 0 }
	}
}
fn outcomes(log string, arch string, phase string) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX READLINKABI OUTCOMES: ordinary=' + ordinary.str() + ' cases=' + case_count(arch).str() + ' failures=' + failures(arch, ordinary, phase).str())
		if phase == 'after-corrected' { assert log.contains('LINUX READLINKABI CONTROLS: ordinary=' + ordinary.str() + ' target-prefix/no-NUL/canaries/aliases/metadata/bytes/cursors/flags/private PASS') }
	}
}
fn native_failure(log string, arch string, phase string) {
	assert log.contains('kind=0 form=0 dest=0 word=0000000000000000 result=0/0 expected=-1/22'), 'native failure markers required'
	assert log.contains('kind=0 form=0 dest=0 word=0000000100000001 result=11/0 expected=1/0')
	assert log.contains('kind=8 form=0 dest=0 word=0000000000000000 result=-1/14 expected=-1/22')
	outcomes(log, arch, phase)
	mut remaining := log
	for ordinary in [1, 0] {
		marker := 'LINUX READLINKABI OUTCOMES: ordinary=' + ordinary.str()
		cohort := remaining.all_before(marker); remaining = remaining.all_after(marker)
		details := cohort.split_into_lines().filter(it.starts_with('LINUX READLINKABI DETAIL:'))
		assert details.len == failures(arch, ordinary, phase)
		for line in details {
			word_text := line.all_after('word=').all_before(' ')
			word := strconv.parse_uint(word_text, 16, 64) or { panic(err) }
			if i32(u32(word)) <= 0 { assert line.contains('expected=-1/22') }
			else {
				assert word_text in ['0000000100000001', '8000000000000003'] || (phase != 'before-corrected' && line.contains('kind=12 '))
				assert line.contains('dest=0') && line.contains('/0 expected=') && !line.contains('expected=-1/')
			}
		}
	}
	assert log.contains('LINUX READLINKABI FAIL: native signed size or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX READLINKABI: PASS')
}
fn expectation_failure(log string, arch string, phase string) {
	outcomes(log, arch, phase)
	mut remaining := log
	for ordinary in [1, 0] {
		marker := 'LINUX READLINKABI OUTCOMES: ordinary=' + ordinary.str()
		cohort := remaining.all_before(marker); remaining = remaining.all_after(marker)
		details := cohort.split_into_lines().filter(it.starts_with('LINUX READLINKABI DETAIL:'))
		assert details.len == failures(arch, ordinary, phase)
		for line in details {
			libc_zero := line.contains('word=0000000000000000') && (line.contains('form=1') || line.contains('form=2'))
			wrong_target := line.contains('kind=12 ') && line.contains('dest=0') && line.contains('/0 expected=')
			assert wrong_target || (phase == 'after' && libc_zero)
		}
	}
	assert log.contains('LINUX READLINKABI FAIL: native signed size or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX READLINKABI: PASS')
}
fn fixture_corrections(root string, area string) ! {
	initial := os.read_file(area + 'initial-fixture.v')!
	intermediate := os.read_file(area + 'intermediate-fixture.v')!
	final_source := os.read_file(root + 'tests/linux-compat/readlinkabifixture/core.v')!
	zero := '\t\t// musl substitutes a one-byte scratch buffer for an exact zero size.\n\t\t// The raw ABI still rejects zero before lookup or buffer access.\n\t\tlibc_zero := word == 0 && form in [i32(1), 2]!\n'
	assert intermediate.count(zero) == 1
	assert intermediate.replace(zero, '').replace('if size <= 0 && !libc_zero {', 'if size <= 0 {').replace('destination != 0 && !libc_zero', 'destination != 0') == initial
	assert final_source.count("C.snprintf(&target[0], 64, c'/sbin/init')") == 1
	assert final_source.replace("C.snprintf(&target[0], 64, c'/sbin/init')", "C.snprintf(&target[0], 64, c'/init')") == intermediate
	assert os.read_file(root + 'tests/native-guest-tools/guesthost/build.v')!.contains("os.cp(init, rootfs + '/sbin/init')!")
	for name in ['readlink', 'readlinkat'] {
		musl := os.read_file(area + 'musl-' + name + '.c')!
		assert musl.contains('char dummy[1];') && musl.contains('if (!bufsize) {') && musl.contains('buf = dummy;') && musl.contains('bufsize = 1;') && musl.contains('if (buf == dummy && r > 0) r = 0;')
	}
	for suffix in ['arm', 'x86'] {
		old := os.read_file(area + 'initial-preview-' + suffix + '.c')!
		mid := os.read_file(area + 'preview-final-' + suffix + '.c')!
		final_c := os.read_file(area + 'preview-corrected-' + suffix + '.c')!
		for name in ['at_form', 'cleanup', 'controls', 'pathname', 'prepare', 'qualify', 'run', 'snapshot', 'storage', 'storage_cycle'] {
			function := 'readlinkabifixture__' + name
			assert canonical_returns(definition(old, function)) == canonical_returns(definition(mid, function))
			assert canonical_returns(definition(mid, function)) == canonical_returns(definition(final_c, function))
		}
		assert canonical_returns(definition(mid, 'readlinkabifixture__probe')).replace('"/init"', '"/sbin/init"') == canonical_returns(definition(final_c, 'readlinkabifixture__probe'))
	}
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX READLINKABI SLAB:') && !line.starts_with('LINUX READLINKABI STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7
		group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0].u64() == pair[1].u64()
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'
			seen[key] = true; rows[group]++
		} else {
			assert fields[4] == 'cycles=200' && fields[6] == 'PASS'
			assert pair[0].u64() == if arch == 'aarch64' { u64(63) } else { u64(160) }
			pages[group]++
		}
	}
	for group in 0 .. 2 { assert rows[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn restore_generated(generated string, baseline string, arch string) {
	name := 'table__syscall_linux_readlinkat'; body := definition(generated, name)
	assert body.contains('i32 size = (i32)((u32)(limit));') && body.contains('if (size <= 0)')
	assert body.contains('return fs__syscall_readlinkat(gpr_state, dirfd, path, buf, (u64)(size));')
	lines := generated.split_into_lines()
	prototypes := lines.filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(';'))
	signatures := lines.filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert prototypes.len == 1 && signatures.len == 1
	block := signatures[0] + body + '\n}\n\n'
	assert generated.count(block) == 1 && generated.count('= ' + name + ';') == 1
	mut restored := generated.replace(prototypes[0] + '\n', '').replace(block, '').replace('= ' + name + ';', '= fs__syscall_readlinkat;')
	if arch == 'x86_64' {
		legacy := 'return table__syscall_linux_readlinkat(gpr_state, fs__at_fdcwd, path, buf, size);'
		assert restored.count(legacy) == 1
		restored = restored.replace(legacy, legacy.replace('table__syscall_linux_readlinkat', 'fs__syscall_readlinkat'))
	}
	assert restored == baseline, 'only readlink size decoding, early rejection and native dispatch may change the whole generated kernel'
	assert definition(generated, 'fs__syscall_readlinkat') == definition(baseline, 'fs__syscall_readlinkat')
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!, 'aarch64', 'before-corrected'); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-readlinkabi-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-corrected-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'ddefb845bae76ffa2b2f98f7b6bf215f0b0efed4'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	changed := ['kernel/syscall/table/linux_common.v', 'kernel/syscall/table/linux_table_amd64.v', 'kernel/syscall/table/syscall_table_arm64.v']
	for path in changed { assert digest(root + path) == inputs[path] }
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	fixture_corrections(root, area)!
	review := root + 'tests/linux-compat/results/2026-10-13/readlinkabi-lifetime-review.md'
	review_text := os.read_file(review)!; assert review_text.starts_with('Independent readlink lifetime review: PASS')
	for path in ['tests/linux-compat/readlinkabifixture/core.v'] { assert review_text.contains(digest(root + path)) }
	for suffix in ['arm', 'x86'] {
		for path in [area + 'preview-corrected-' + suffix + '.c', area + 'kernel-' + suffix + '/kernel/obj/blob.c', area + 'after-corrected-' + suffix + '.log'] { assert review_text.contains(digest(path)) }
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
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!, arch)
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log'), 'coverage_check': digest(area + 'coverage-check.log'),
			'musl_readlink_source': digest(area + 'musl-readlink.c'), 'musl_readlinkat_source': digest(area + 'musl-readlinkat.c'), 'guest_build_source': digest(root + 'tests/native-guest-tools/guesthost/build.v'), 'lifetime_review': digest(review)}
		for phase in ['before', 'after'] {
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!
			assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device')
			artifacts[phase + '_build'] = digest(build)
		}
		for phase in ['before', 'after', 'before-final', 'after-final', 'before-corrected', 'after-corrected'] {
			initial := phase in ['before', 'after']; intermediate := phase in ['before-final', 'after-final']; baseline := phase.starts_with('before')
			state := area + phase + '-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if baseline { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase in ['after', 'after-final'] { 5 } else { 1 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if baseline || (name == 'readlinkabi' && phase != 'after-corrected') { 1 } else { 0 }
				wanted_source := if name == 'readlinkabi' && initial { area + 'initial-fixture.v' } else if name == 'readlinkabi' && intermediate { area + 'intermediate-fixture.v' } else { root + 'tests/linux-compat/' + name + 'fixture/core.v' }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(wanted_source)
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'readlinkabi' {
					preview := if initial { 'initial-preview-' } else if intermediate { 'preview-final-' } else { 'preview-corrected-' }
					assert digest(c) == digest(area + preview + suffix + '.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if baseline { native_failure(log, arch, phase) }
					else if phase == 'after-corrected' { outcomes(log, arch, phase); retention(log, arch) }
					else { expectation_failure(log, arch, phase) }
				} else {
					assert log.contains('LINUX ' + name.to_upper() + ': PASS')
					if phase == 'after-final' { assert artifacts[phase + '_' + name + '_generated_c'] == artifacts['after_' + name + '_generated_c'] }
				}
			}
			if phase in ['after', 'after-final'] {
				assert names == ['readlinkabi', 'open', 'pathio', 'namespace', 'runtime']
				assert !log.contains('Linux compatibility guest suite: PASS')
			} else { assert names == ['readlinkabi']; if phase == 'after-corrected' { assert log.contains('Linux compatibility guest suite: PASS') } }
			publish(state + 'receipt.json', out + 'readlinkabi-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'readlinkabi-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before-corrected_readlinkabi_generated_c'] == artifacts['after-corrected_readlinkabi_generated_c']
		context := 'Native musl ELF64 readlink/readlinkat signed32 sizes:4320 ARM/5760 x86 checks cover sixteen path classes, fifteen words and three destinations in root/UID1000 groups. The adapter rejects nonpositive low signed32 sizes with EINVAL before path/fd/policy/destination access; positive sizes ignore upper bits. Musl exact zero intentionally uses scratch lookup and returns0 or a real path error. Initial/intermediate fixture expectation mistakes and all failed logs/receipts remain visible: libc-zero behavior and /sbin/init staging, verified against captured musl source and guest builder. Source corrections are confined to probe; all other generated functions stay identical after normalizing compiler return/unused-loop names. Final baselines fail712 ordinary/718 root on ARM and980 ordinary/988 root on x86; every final failure is invalid signed32 size or excessive upper-bit copying. Final candidates have zero failures. Six stable FDs plus a transient alias survive32 warmups/200 measured cycles of52 probes plus one relative copy/control with all live slabs/big pages flat. Exact target prefixes/no-NUL/canaries, directory-relative/absolute-ignored-FD/dangling/private/procfs behavior, real lookup/type/permission/copy errors, aliases/metadata/bytes/cursors/flags remain checked. Loop/bad pathname pointers stay outside storage. Reversing the scalar adapter/dispatch/legacy routing restores the entire baseline kernel C; callee ownership is byte-identical. All before/after actual fixture C matches its architecture/version preview without hidden allocation. Both original and intermediate candidate aggregates independently pass open/pathio/namespace/runtime while retaining failed new-fixture verdicts; final new-fixture suites pass on identical kernels. Eight host files and inventory checks pass. Allocation allowance failures retain406 ARM/295 x86 sites and exact NEW rows. All63 isolated inputs and build/compiler/kernel/C/source/init/ISO/log/receipt hashes are pinned; both audit negative controls execute. Empty-path symlink descriptors, Linux procfs target spelling, link atime, restrictive MAC, concurrency, partial-copy boundaries, disk/overlays, GNU/translated/ELF32 and full installation/sandbox/portal/runtime acceptance remain separate.'
		os.write_file(out + 'readlinkabi-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control', 'coverage-check', 'build-before-arm', 'build-before-x86', 'build-after-arm', 'build-after-x86'] {
		publish(area + name + '.log', out + 'readlinkabi-' + name + '.log')!
	}
	println('Native readlink size qualification audit: PASS')
}
