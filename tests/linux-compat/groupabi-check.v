// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr,voidptr,u32) i32
fn C.CC_SHA256_Final(&u8,voidptr) i32
struct Evidence { architecture string context string base_commit string artifacts map[string]string source_inputs map[string]string }

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before','after'] && arch in ['aarch64','x86_64']
	topology := log.split_into_lines().filter(it.starts_with('LINUX GROUPABI TOPOLOGY:'))
	assert topology.len == 2
	mut seen := map[string]bool{}
	for row in topology {
		fields := row.fields(); assert fields.len == 13
		assert fields[3] in ['ordinary=0','ordinary=1'] && fields[3] !in seen; seen[fields[3]] = true
		assert fields[4] == if fields[3] == 'ordinary=0' { 'uid=0' } else { 'uid=1000' }
		for index,prefix in {5:'self=',6:'sid=',7:'leader=',8:'member=',9:'outsider=',10:'dead='} { assert fields[index].starts_with(prefix) }
		self := fields[5].all_after('=').int(); assert self > 1 && fields[6].all_after('=').int() == self
		mut identities := map[int]bool{}; identities[self] = true
		for index in [7,8,9,10] { id := fields[index].all_after('=').int(); assert id > 0 && id !in identities; identities[id] = true }
		assert fields[11].starts_with('outsider_group=') && fields[12].starts_with('outsider_session=')
		assert fields[11].all_after('=').int() >= 0 && fields[12].all_after('=').int() >= 0 && fields[12].all_after('=').int() != self
		if reference { assert fields[11] == 'outsider_group=0' && fields[12] == 'outsider_session=0' }
	}
	mut cases := map[string]string{}
	for label in ['CASES:','FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX GROUPABI ' + label)); assert rows.len == 8
		seen.clear(); mut calls := 0; mut failures := 0
		for row in rows {
			fields := row.fields(); assert fields.len == 7
			assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['kind=0','kind=1','kind=2','kind=3']
			assert fields[5].starts_with('calls=') && fields[6].starts_with('failures=')
			key := fields[3] + fields[4]; assert key !in seen; seen[key] = true
			kind := fields[4].all_after('=').int(); n := fields[5].all_after('=').int(); f := fields[6].all_after('=').int()
			assert n == [160,192,2496,32]![kind]
			assert f == if phase == 'before' { [82,165,990,14]![kind] } else { 0 }
			if label == 'CASES:' { cases[key] = fields[5] + fields[6] } else { assert cases[key] == fields[5] + fields[6] }
			calls += n; failures += f
		}
		assert calls == 5760 && failures == if phase == 'before' { 2502 } else { 0 }
	}
	if phase == 'before' { assert log.contains('LINUX GROUPABI DETAIL:') && log.contains('LINUX GROUPABI FAIL:') && !log.contains('LINUX GROUPABI: PASS') }
	else { assert !log.contains('LINUX GROUPABI DETAIL:') && !log.contains('LINUX GROUPABI FAIL:') }
	if reference { assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX GROUPABI REFERENCE: PASS') && !log.contains('LINUX GROUPABI STORAGE:') }
	else if phase == 'after' { assert log.count('LINUX GROUPABI: PASS') == 1 }
	assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn check_source(area string, root string) ! {
	for file,path in {'linux_common.v':'kernel/syscall/table/linux_common.v','job_groups.v':'kernel/proc/job_groups.v','cred.v':'kernel/userland/cred.v','coverage.v':'tools/linux-compat/coverage.v'} {
		before := os.read_file(area + 'before-' + file)!
		after := os.read_file(area + 'after-' + file)!
		mut expected := before
		if file == 'linux_common.v' {
			expected = expected.replace('return proc.set_process_group(pid, pgid)','return proc.set_process_group(int(i32(pid)), int(i32(pgid)))')
			expected = expected.replace('return proc.get_process_group(pid)','return proc.get_process_group(int(i32(pid)))')
		} else if file == 'cred.v' {
			expected = expected.replace('return proc.get_process_session(pid)','return proc.get_process_session(int(i32(pid)))')
		} else if file == 'job_groups.v' {
			expected = expected.replace('if pid < 0 || pgid < 0 { return errno.err, errno.einval }','if pgid < 0 || (pid < 0 && pgid == 0) { return errno.err, errno.einval }\n\tif pid < 0 { return errno.err, errno.esrch }')
			expected = expected.replace('if pid < 0 { return errno.err, errno.einval }','if pid < 0 { return errno.err, errno.esrch }')
		} else {
			expected = expected.replace("\t\t'kernel/proc/pidns.v',\n","\t\t'kernel/proc/pidns.v',\n\t\t'kernel/proc/job_groups.v', 'kernel/userland/cred.v',\n")
		}
		exact := after == expected && after != before; assert exact, 'Only bounded entry normalization, negative-ID errors and new semantic-source fingerprints may change: ' + path
		assert digest(root + path) == digest(area + 'after-' + file)
		for suffix in ['arm','x86'] { assert digest(area + 'kernel-' + suffix + '/' + path) == digest(root + path) }
	}
}

fn check_c(area string, suffix string) ! {
	mut before := os.read_file(area + 'before-' + suffix + '.c')!
	mut after := os.read_file(area + 'after-' + suffix + '.c')!
	for name in ['table__syscall_linux_setpgid','table__syscall_linux_getpgid','userland__syscall_getsid','proc__set_process_group','proc__get_process_group','proc__get_process_session'] {
		marker := '\nmulti_return_u64_u64 ' + name + '('
		// Skip the declaration and locate the actual definition.
		old_marker := before.all_after(marker).all_before('\n')
		mut old_start := marker + old_marker
		if !old_marker.ends_with('{') {
			start := before.index(marker) or { panic(name) }; second := before[start+marker.len..].index(marker) or { panic('missing body ' + name) }
			body_start := start + marker.len + second; old_start = '\n' + before[body_start+1..].all_before('\n')
		}
		new_start := old_start
		old := definition(before,old_start); new := definition(after,new_start)
		assert old != new
		for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc('] { assert old.count(token) == new.count(token), name + token }
		before = before.replace(old,''); after = after.replace(new,'')
	}
	unchanged := before == after; assert unchanged, 'Whole C differs outside six qualified functions; no compiler normalization permitted'
}

fn retained_diagnostics(area string, out string) ! {
	pins := object(area + 'diagnostic-inputs.json')!
	assert pins.len > 30
	for path,hash in pins { assert path.starts_with(area) && os.inode(path).typ == .regular && digest(path) == hash.str(),path }
	failed := object(area + 'states/p1-before-arm/receipt.json')!
	rows := failed['results']!.as_array(); assert rows.len == 1
	row := rows[0].as_map(); assert row['name']!.str() == 'groupabi' && row['exit_code']!.int() == 1
	assert row['detail']!.str() == 'Command failed' && row['init_sha256']!.str() == '' && row['iso_sha256']!.str() == ''
	assert !os.exists(area + 'states/p1-before-arm/groupabi/init')
	link := os.read_file(area + 'states/p1-before-arm.log')!
	assert link.contains('cannot open crtbeginT.o') && link.contains('unable to find library -lpthread')
	reference := object(area + 'states/p1-reference-x86/receipt.json')!
	assert !reference['passed']!.bool()
	log := os.read_file(area + 'states/p1-reference-x86/serial.log')!
	assert log.count('LINUX GROUPABI FAIL: setup stage=15') == 2 && !log.contains('LINUX GROUPABI FINAL:')
	assert log.contains('Attempted to kill init!')
	old := os.read_file(area + 'exploratory-probe.v')!
	final := os.read_file('/Users/alex/code/vinix/tests/linux-compat/groupabifixture/core.v')!
	expected := old.replace('outsider_group <= 0 || outsider_session <= 0','outsider_group < 0 || outsider_session < 0 || outsider_session == self').replace('outsider=%d dead=%d\\n\',i32(ordinary),uid,self,self,a.pid,b.pid,outsider,dead)', 'outsider=%d dead=%d outsider_group=%d outsider_session=%d\\n\',i32(ordinary),uid,self,self,a.pid,b.pid,outsider,dead,outsider_group,outsider_session)')
	exact := final == expected; assert exact, 'Only the legitimate zero outside identity precondition and its printed values may change'
	for name,path in {
		'initial-link-refusal.log': area + 'states/p1-before-arm.log'
		'initial-link-receipt.json': area + 'states/p1-before-arm/receipt.json'
		'exploratory-reference.log': area + 'states/p1-reference-x86/serial.log'
		'exploratory-reference-receipt.json': area + 'states/p1-reference-x86/receipt.json'
		'exploratory-probe.v': area + 'exploratory-probe.v'
		'diagnostic-inputs.json': area + 'diagnostic-inputs.json'
		'primary-fetch-refusal.log': area + 'initial-fetch.log'
		'primary-reuse.json': area + 'primary-reuse.json'
	} { publish(path,out + 'groupabi-' + name)! }
}

fn sdk_and_primary(area string, out string) ! {
	sdk := object(area + 'sdk-inputs.json')!
	assert sdk.len > 1000
	for path,hash in sdk { assert digest(area + 'sdk/' + path) == hash.str(),path }
	primary := object(area + 'primary-reuse.json')!
	assert primary['source_url']!.str() == 'https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c'
	assert primary['sha256']!.str() == 'e43eb875410d607ccf91ca00d88433052b58fdae4e4ccdd12c53c458f1ce1d69'
	assert digest(area + 'linux-sys-v6.12.c') == primary['sha256']!.str()
	assert digest(primary['cached_source']!.str()) == primary['sha256']!.str()
	assert os.read_file('/Users/alex/.cache/vinix-linux-compat/niceabi-20261015/linux-source.sha256')!.trim_space() == primary['sha256']!.str() + ' ' + primary['source_url']!.str()
	assert os.read_file(area + 'initial-fetch.log')!.contains('error: 429')
	for path in ['states/p3-before-arm/groupabi','states/p2-after-arm/groupabi','states/p2-after-arm/runtime','states/p2-after-arm/randomsignal','states/p2-reference-arm'] {
		for file in ['fixture.o','serial.o','init'] {
			receipt := object(area + path + '/' + file + '.compiler.json')!
			assert receipt['status']!.str() == '0' && receipt['output']!.str() == ''
			assert receipt['arguments']!.str().contains('--gcc-install-dir=' + area.trim_right('/') + '/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
			assert receipt['arguments']!.str().contains('--target=aarch64-linux-musl') && receipt['arguments']!.str().contains('--sysroot=' + area.trim_right('/') + '/sdk')
		}
	}
	publish(area + 'sdk-inputs.json',out + 'groupabi-sdk-inputs.json')!
}

fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}
		state.checksum_into(mut result)
		return result.hex()
	}
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}

fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) {
		assert os.read_bytes(output)! == data
	} else {
		os.write_file_array(output, data)!
	}
}

fn git(tree string, args []string) !string {
	mut p := os.new_process('git')
	p.set_args(['-C', tree, ...args])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	assert code == 0, output
	return output.trim_space()
}

fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable())
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
	return output
}

fn storage(log string, arch string, phase string) {
	mut slabs := [2]int{}
	mut pages := [2]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX GROUPABI SLAB:') || it.starts_with('LINUX GROUPABI STORAGE:')) {
		fields := row.fields()
		assert fields.len == 7 && fields[3].starts_with('ordinary=')
		ordinary := fields[3].all_after('=').int()
		assert ordinary in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' {
			assert fields[4].starts_with('size=') && fields[6] == 'cycles=200'
			key := fields[3] + fields[4]
			assert key !in seen
			seen[key] = true
			slabs[ordinary]++
		} else {
			assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0
			pages[ordinary]++
		}
	}
	for ordinary in 0 .. 2 {
		assert slabs[ordinary] == if phase == 'before' {
			0
		} else if arch == 'aarch64' {
			18
		} else {
			14
		}
		assert pages[ordinary] == if phase == 'before' { 0 } else { 1 }
	}
}

fn failure(log string, arch string) {
	assert log.contains('LINUX GROUPABI DETAIL:'), 'groupabi baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == names.len
	mut artifacts := {
		'receipt': digest(state + '/receipt.json')
	}
	artifacts['aggregate'] = digest(state + '.log')
	for index, row in rows {
		entry := row.as_map()
		name := entry['name']!.str()
		assert name == names[index] && entry['exit_code']!.int() == if failing && index == 0 {
			1
		} else {
			0
		} && entry['detail']!.str() == ''
		for label, path in {
			'source': state + '/sources/' + name + 'fixture/core.v'
			'init':   state + '/' + name + '/init'
			'iso':    state + '/' + name + '/test.iso'
		} {
			hash := digest(path)
			key := if label == 'source' {
				'source_sha256'
			} else if label == 'init' {
				'init_sha256'
			} else {
				'iso_sha256'
			}
			assert hash == entry[key]!.str()
			artifacts[name + '_' + label] = hash
		}
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c')
		artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing || index > 0 {
			assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS')
		}
	}
	return artifacts
}

fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str())
	assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {
		'kernel':            state + '/linux'
		'probe':             state + '/probe'
		'wrapper_source':    state + '/source/groupabireferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/groupabi-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/groupabireferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true)
	return artifacts
}

fn definition(source string, marker string) string {
	start := source.index(marker) or { panic('missing complete definition: ' + marker) }
	mut depth := 0
	mut entered := false
	for position in start .. source.len {
		if source[position] == `{` {
			depth++
			entered = true
		} else if source[position] == `}` {
			depth--
			if entered && depth == 0 { return source[start..position + 1] }
		}
	}
	panic('unclosed function definition')
}

fn main() {
	if '--negative-control' in os.args {
		assert false, 'groupabi assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: groupabi-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	retained_diagnostics(area, out)!
	sdk_and_primary(area, out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'groupabi assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p2-reference-arm/serial.log', 'aarch64'], 'groupabi baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in three syscall entry casts and three group/session helpers; exact signed32 normalization, query ESRCH and setpgid EINVAL/ESRCH precedence; existing table locking, borrowed processes, orphan stack descriptor and group mutation/notification are unchanged; no added allocation/free and no compiler normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'fe594a9c126944d7848ac0f7f6a83fce7fe8ea99'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	pins := object(compiler_root + 'compiler-inputs.json')!
	assert pins.len == 15146
	assert pins['v']!.str() == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash.str(), path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	before_alloc := os.read_file(area + 'allocs-before.log')!
	after_alloc := os.read_file(area + 'allocs-after.log')!
	assert before_alloc == after_alloc, 'Allocation diagnostics must remain byte-identical'
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		assert before_alloc.split_into_lines().filter(it.starts_with(arch + ':')).len == 1
		assert before_alloc.contains(count + ' allocation sites (V exit 0)') && before_alloc.contains('NEW:')
	}
	assert os.read_file(area + 'coverage-before-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-sys-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c'
	linux_source := os.read_file(area + 'linux-sys-v6.12.c')!
	assert linux_source.contains('SYSCALL_DEFINE1(getpgid, pid_t, pid)') && linux_source.contains('SYSCALL_DEFINE1(getsid, pid_t, pid)') && linux_source.contains('SYSCALL_DEFINE2(setpgid, pid_t, pid, pid_t, pgid)')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p3-before-arm/') || path.starts_with(states + 'p2-before-x86/') || path.starts_with(states + 'p2-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['groupabi']
			} else {
				['groupabi', 'runtime', 'randomsignal']
			}
			for name in names {
				probe := states + if phase == 'before' && suffix == 'arm' { 'p3-' } else { 'p2-' } + phase + '-' + suffix + '/' + name
				completed['Completed ' + probe + ': captured files byte-identical; disposable boot staging retired'] = true
				assert !os.exists(probe + '/iso-build') && !os.exists(probe + '/efivars.fd')
				mut count := 0
				for path in os.walk_ext(probe, '') {
					if os.inode(path).typ != .regular { continue }
					assert path in retained && path !in walked
					walked[path] = true
					count++
				}
				assert count == if suffix == 'arm' { 12 } else { 9 }
			}
		}
	}
	assert walked.len == retained.len
	for row in os.read_file(area + 'watch.log')!.split_into_lines() {
		assert row in completed
		completed.delete(row)
	}
	assert completed.len == 0
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/proc/job_groups.v\nkernel/syscall/table/linux_common.v\nkernel/userland/cred.v'
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 66
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 64
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
			if path in ['kernel/proc/job_groups.v','kernel/userland/cred.v'] {
				assert path !in before_inputs && git(tree,['show',base + ':' + path])!.trim_space() == os.read_file(area + 'before-' + os.file_name(path))!.trim_space()
			} else if path in ['kernel/syscall/table/linux_common.v','tools/linux-compat/coverage.v'] {
				assert before_inputs[path] == digest(area + 'before-' + os.file_name(path))
			} else { assert before_inputs[path] == hash }
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/syscall/table/linux_common.v')
			'kernel_source_before':     digest(area + 'before-linux_common.v')
			'fixture_source':           digest(root + 'tests/linux-compat/groupabifixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-sys-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'primary_reuse': digest(area + 'primary-reuse.json')
			'diagnostic_inputs': digest(area + 'diagnostic-inputs.json')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-retained-inputs.json')
			'watch_log':                digest(area + 'watch.log')
		}
		for name in ['manage.v', 'manage', 'watch.v', 'watch', 'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + if phase == 'before' && suffix == 'arm' { 'p3-' } else { 'p2-' } + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['groupabi']
			} else {
				['groupabi', 'runtime', 'randomsignal']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['groupabi_source', 'groupabi_init', 'groupabi_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/groupabi/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + if phase == 'before' { 'initial-build-' + suffix + '-before.log' } else { 'build-after-' + suffix + '-detached.log' }
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/groupabi/serial.log'
				'build':     build
			} {
				publish(path, out + 'groupabi-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'groupabi' { continue }
					publish(state + '/' + name + '/serial.log', out + 'groupabi-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + if suffix == 'arm' { 'p3-before-' } else { 'p2-before-' } + suffix + '/groupabi'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 4
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p2-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['groupabi_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'groupabi-reference-' + arch + '-' + label + if label == 'receipt' {
				'.json'
			} else {
				'.log'
			})!
			artifacts['reference_' + label] = digest(path)
		}
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
			'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] {
			artifacts[name] = digest(area + name)
		}
		os.write_file(out + 'groupabi-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native leader getpgid/getsid/setpgid signed32 words and negative errors,5760 root/UID1000 controls per architecture. Each cohort:160 current/zero/held-child/other-session/reaped/negative/range queries,192 successful child group assignments,2496 exact setter error-priority controls and32 WNOWAIT/reaped queries. Seven raw word forms plus genuine musl calls; setter words vary independently. Original2502 failures each, corrected and identical-ELF Linux6.12.51 zero. Every case checks caller/group-leader/member/outsider group and session state, successful setters verify the new group, and blocked children are explicitly released/reaped. Two warmed200-cycle query/refusal and alternating real group mutations measure all slabs/pages. Four production builds, runtime/randomsignal regressions, unchanged allocation diagnostics, private SDK and adapter receipts,15,146 compiler pins,64-to66 semantic input inventories, six-function whole-C scope and executing audit negatives. First missing runtime-link refusal, HTTP429 cached-source recovery and Linux PID1 group/session-zero setup refusal are retained. Kernel adds only scalar entry casts and error branches, preserving existing ownership, table locking, stack orphan descriptor and notification lifetime. Worker TIDs, namespace depth, exec/exit/credential races, zombie setters, terminal/job-control signaling, PID reuse, GNU/translated/ELF32 paths and three broad roadmap gates remain separate.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		},
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log',
		'coverage-before-check.log'] {
		publish(area + name, out + 'groupabi-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'groupabi-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native groupabi conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'groupabi-audit.log')!
	println('Native groupabi conformance audit: PASS')
}
