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
fn native_failure(log string) {
	assert log.contains('kind=0 alias=0 raw=1 high=0000000000000000 dest=0 word=0000000000000001 result=-1/2 expected=1/0'), 'empty-path failure markers required'
	assert log.contains('kind=2 alias=0 raw=1 high=0000000100000000 dest=0 word=0000000000000003 result=-1/2 expected=3/0')
	assert log.contains('kind=12 alias=0 raw=1 high=deadbeef00000000 dest=0 word=0000000000000001 result=-1/2 expected=-1/9')
	mut remaining := log
	for ordinary in [1, 0] {
		marker := 'LINUX READLINKEMPTY OUTCOMES: ordinary=' + ordinary.str()
		assert remaining.contains(marker + ' cases=3648 failures=1197')
		cohort := remaining.all_before(marker); remaining = remaining.all_after(marker)
		details := cohort.split_into_lines().filter(it.starts_with('LINUX READLINKEMPTY DETAIL:'))
		assert details.len == 1197 && details.all(it.contains('result=-1/2'))
		assert details.filter(it.contains('expected=-1/9')).len == 63
		assert details.filter(it.contains('expected=-1/14')).len == 720
		assert details.filter(it.contains('/0')).len == 414
	}
	assert log.contains('LINUX READLINKEMPTY FAIL: empty-path target or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX READLINKEMPTY: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX READLINKEMPTY OUTCOMES: ordinary=' + ordinary.str() + ' cases=3648 failures=0')
		assert log.contains('LINUX READLINKEMPTY CONTROLS: ordinary=' + ordinary.str() + ' linked/dangling/unlinked/private/procfs/target-prefix/no-NUL/canaries/aliases/metadata/bytes/cursors/flags/queued-AB PASS')
	}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX READLINKEMPTY SLAB:') && !line.starts_with('LINUX READLINKEMPTY STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7
		group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0].u64() == pair[1].u64()
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'
			seen[key] = true; rows[group]++
		} else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; assert pair[0].u64() == if arch == 'aarch64' { u64(70) } else { u64(181) }; pages[group]++ }
	}
	for group in 0 .. 2 { assert rows[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn restore_generated(generated string, baseline string) {
	name := 'fs__readlink_node'; body := definition(generated, name); lines := generated.split_into_lines()
	prototypes := lines.filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(';'))
	signatures := lines.filter(!it.starts_with(' ') && !it.starts_with('\t') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert prototypes.len == 1 && signatures.len == 1
	block := signatures[0] + body + '\n}\n\n'; assert generated.count(block) == 1
	mut restored := generated.replace(prototypes[0] + '\n', '').replace(block, '')
	current := definition(restored, 'fs__syscall_readlinkat'); previous := definition(baseline, 'fs__syscall_readlinkat')
	assert current.contains('file__fd_from_fdnum(process, (i64)((i32)(dirfd)))') && current.count('fs__readlink_node(node, buf, limit)') == 2
	assert current.contains('file__FD__unref(fd);') && current.contains('errno__enoent')
	assert restored.count(current) == 1; restored = restored.replace(current, previous)
	assert restored == baseline, 'only readlinkat FD handling and extracted helper may change whole kernel C'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/readlinkempty-20261013/'; compiler := '/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	if '--kernel-control' in os.args {
		for suffix in ['arm', 'x86'] { restore_generated(os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!) }
		println('Empty-path kernel scope: PASS'); return
	}
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'empty-path failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '49cee5ac7dcb554339b00b7d413ac5c569ad40f7'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(root + 'kernel/fs/vfs.v') == inputs['kernel/fs/vfs.v']
	assert git(compiler, ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git(compiler, ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	review := root + 'tests/linux-compat/results/2026-10-13/readlinkempty-lifetime-review.md'
	review_text := os.read_file(review)!; assert review_text.starts_with('Independent empty-path readlink lifetime review: PASS')
	for path in ['kernel/fs/vfs.v', 'tests/linux-compat/readlinkemptyfixture/core.v'] { assert review_text.contains(digest(root + path)) }
	for suffix in ['arm', 'x86'] {
		for path in [area + 'preview-' + suffix + '.c', area + 'kernel-' + suffix + '/kernel/obj/blob.c', area + 'after-' + suffix + '/readlinkempty/serial.log'] { assert review_text.contains(digest(path)) }
	}
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} { assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)') }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/fs/vfs.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		old_source := git(tree, ['show', base + ':kernel/fs/vfs.v'])! + '\n'; new_source := os.read_file(tree + 'kernel/fs/vfs.v')!
		old_body := definition(old_source, 'syscall_readlinkat'); new_body := definition(new_source, 'readlink_node')
		assert old_body.all_after('\tnode := get_node(parent, path, false) or { return errno.err, errno.get() }\n') == new_body.trim_left('\n')
		mut artifacts := {'compiler': digest(compiler + 'v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'), 'audit': digest(@FILE),
			'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log'), 'coverage_check': digest(area + 'coverage-check.log'),
			'host_cleanup': digest(area + 'host-cleanup.txt'), 'compiler_build_failed': digest(area + 'compiler-build.log'), 'compiler_build_retry': digest(area + 'compiler-build-retry.log'),
			'compiler_native_build': digest(area + 'compiler-native-build.log'), 'bootstrap_controller_failure': digest(area + 'controller-bootstrap-build.log'), 'lifetime_review': digest(review)}
		for phase in ['before', 'after'] {
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!
			assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device'); artifacts[phase + '_build'] = digest(build)
			state := area + phase + '-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 5 }; mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'readlinkempty' {
					assert digest(c) == digest(area + 'preview-' + suffix + '.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log) } else { retention(log, arch) }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' { assert names == ['readlinkempty', 'readlinkabi', 'open', 'pathio', 'runtime'] && log.contains('Linux compatibility guest suite: PASS') } else { assert names == ['readlinkempty'] }
			publish(state + 'receipt.json', out + 'readlinkempty-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'readlinkempty-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_readlinkempty_generated_c'] == artifacts['after_readlinkempty_generated_c']
		context := 'Native musl ELF64 readlinkat empty-path FD targets:7296 root/UID1000 checks per architecture cover named/dangling/unlinked/private/procfs self/exe symlinks, ordinary/O_PATH regular files, directories, null, pipe/socket and invalid/FDCWD handles, aliases, signed32 size/FD words, raw/musl scratch-zero behavior and valid/null/inaccessible buffers. Baselines fail1197/cohort:414 target/scratch copies,720 destination-fault refusals and63 invalid-FD EBADF expectations returnENOENT. Candidate probes require exact target prefixes/no-NUL/canaries, retained inode/device/mode/size/UID/GID/nlink/FD flags/shared cursors/AB queues and private/missing pathname refusals. Parent retains35 descriptors and each child adds3 exe aliases; all38 survive warmups and200 cycles of56 probes plus3 transient dup/copy controls with flat slabs and70ARM/181x86 big pages. Aliases share open-file descriptions. The held FD/Handle pins node/resource/target through helper return after unlink; every return releases it, with existing path/dynamic-target frees unchanged. Independent final generated-lifetime/source/capture/retention review approves. Only fs/vfs.v differs; moving the helper and restoring the handler reproduces the whole baseline C and the helper source is the original tail. All actual before/after fixture C matches previews without hidden allocation. Both candidates also pass readlinkabi/open/pathio/runtime; eight host files/inventory pass. Allocation audit retains406 ARM/295 x86 failures and exact NEW rows. A concurrent cleanup removed /tmp qualification/compiler areas during initial unqualified builds; published prior commits/receipts and root edits survive. Fresh baseline/candidate kernels and clean f635 compiler rebuilds live in a persistent area; bootstrap dependency/segmentation failures remain pinned. All63 isolated semantic inputs and compiler/controller/build/kernel/C/source/init/ISO/log/receipt hashes are bound; both negative controls execute. Linux procfs spelling, atime, restrictive policy, close/unlink races, partial-copy boundaries, disk/overlays and GNU/translated/ELF32/installation/sandbox/portal/runtime acceptance remain separate.'
		os.write_file(out + 'readlinkempty-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control', 'coverage-check', 'build-before-arm', 'build-before-x86', 'build-after-arm', 'build-after-x86', 'compiler-build', 'compiler-build-retry', 'compiler-native-build', 'controller-bootstrap-build'] { publish(area + name + '.log', out + 'readlinkempty-' + name + '.log')! }
	publish(area + 'host-cleanup.txt', out + 'readlinkempty-host-cleanup.txt')!
	println('Native empty-path readlink qualification audit: PASS')
}
