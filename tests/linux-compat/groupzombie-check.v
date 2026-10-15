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

fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after'] && arch in ['aarch64','x86_64']
 rows := log.split_into_lines().filter(it.starts_with('LINUX GROUPZOMBIE TOPOLOGY:')); assert rows.len == 20
 mut seen := map[string]bool{}; mut ids := map[string]bool{}; mut targets := map[string]string{}; mut execs := map[string]int{}
 for row in rows {
  fields := row.fields(); assert fields.len == 13
  assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
  assert fields[5] == if fields[3] == 'ordinary=0' {'uid=0'} else {'uid=1000'}
  for index,prefix in {6:'self=',7:'kind=',8:'pid=',9:'group=',10:'session=',11:'executed=',12:'zombie='} {assert fields[index].starts_with(prefix)}
  self := fields[6].all_after('=').int(); kind := fields[7].all_after('=').int(); pid := fields[8].all_after('=').int(); assert self > 1 && kind >= 0 && kind < 5 && pid > 1 && pid != self
  if fields[4] == 'namespace=1' {assert self == 2}
  cohort := fields[3]+fields[4]; key := cohort+fields[7]; assert key !in seen; seen[key] = true; targets[key] = fields[8]
  id_key := cohort+fields[8]; assert id_key !in ids; ids[id_key] = true
  group := if kind == 0 || kind == 2 || kind == 3 {pid} else {self}; session := if kind == 2 || kind == 3 {pid} else {self}
  assert fields[9].all_after('=').int() == group && fields[10].all_after('=').int() == session
  executed := kind == 1 || kind == 3; assert fields[11] == if executed {'executed=1'} else {'executed=0'}
  assert fields[12] == if kind < 4 {'zombie=1'} else {'zombie=0'}
  if executed {event := fields[7]+fields[8]+'parent='+self.str()+fields[9]+fields[10]+fields[5]; execs[event]++}
 }
 exec_rows := log.split_into_lines().filter(it.starts_with('LINUX GROUPZOMBIE EXEC:')); assert exec_rows.len == 8
 for row in exec_rows {fields := row.fields(); assert fields.len == 9; event := fields[3..].join(''); assert event in execs && execs[event] > 0; execs[event]--}
 for _,count in execs {assert count == 0}
 for label in ['EXIT:','REAP:'] {
  edges := log.split_into_lines().filter(it.starts_with('LINUX GROUPZOMBIE '+label)); assert edges.len == 16; seen.clear()
  for row in edges {
   fields := row.fields(); assert fields.len == if label == 'EXIT:' {10} else {8}
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1'] && fields[5] in ['kind=0','kind=1','kind=2','kind=3']
   key := fields[3]+fields[4]+fields[5]; assert key !in seen && targets[key] == fields[6]; seen[key] = true
   if label == 'EXIT:' {assert fields[7] == 'wait=CLD_EXITED' && fields[8] == 'poll=POLLIN' && fields[9] == 'status=0'} else {assert fields[7] == 'status=0'}
  }
 }
 mut cases := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  outcomes := log.split_into_lines().filter(it.starts_with('LINUX GROUPZOMBIE '+label)); assert outcomes.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in outcomes {
   fields := row.fields(); assert fields.len == 8
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1'] && fields[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true
   assert fields[6].starts_with('calls=') && fields[7].starts_with('failures=')
   kind := fields[5].all_after('=').int(); n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
   assert n == [448,448,448,448,512,1984]![kind]
   assert f == if phase == 'before' {[320,320,320,320,64,0]![kind]} else {0}
   if label == 'CASES:' {cases[key] = fields[6]+fields[7]} else {assert cases[key] == fields[6]+fields[7]}
   calls += n; failures += f
  }
  assert calls == 17152 && failures == if phase == 'before' {5376} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX GROUPZOMBIE DETAIL:') && log.contains('LINUX GROUPZOMBIE FAIL:') && !log.contains('LINUX GROUPZOMBIE: PASS')}
 else {assert !log.contains('LINUX GROUPZOMBIE DETAIL:') && !log.contains('LINUX GROUPZOMBIE FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX GROUPZOMBIE REFERENCE: PASS') && !log.contains('LINUX GROUPZOMBIE STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX GROUPZOMBIE: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-job_groups.v')!; after := os.read_file(area+'after-job_groups.v')!
 expected := before.replace('target == unsafe { nil } || target.exiting','target == unsafe { nil } || (target.exiting && !target.exit_published)')
  .replace('member == unsafe { nil } || member.exiting','member == unsafe { nil } || (member.exiting && !member.exit_published)')
 exact := after == expected && after != before; assert exact,'Only completed zombies gain target and destination eligibility; incomplete teardown remains excluded'
 assert digest(root+'kernel/proc/job_groups.v') == digest(area+'after-job_groups.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/proc/job_groups.v') == digest(area+'after-job_groups.v')}
}

fn body(source string,name string) string {
 rows := source.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with('{'))
 assert rows.len == 1,name
 return definition(source,'\n'+rows[0])
}
fn check_c(area string,suffix string) ! {
 mut before := os.read_file(area+'before-'+suffix+'.c')!; mut after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'proc__set_process_group'); new := body(after,'proc__set_process_group'); assert old != new
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_thread(','unpin_thread('] {assert old.count(token) == new.count(token),token}
 before = before.replace(old,''); after = after.replace(new,'')
 unchanged := before == after; assert unchanged,'Whole production C differs outside set_process_group; no normalization'
}


fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; assert sdk.len == 2014
 prior := object('/Users/alex/.cache/vinix-linux-compat/grouporder-20261015/sdk-inputs.json')!; assert sdk.len == prior.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 primary := object(area+'primary-reuse.json')!
 assert primary['source_url']!.str() == 'https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c'
 assert primary['sha256']!.str() == 'e43eb875410d607ccf91ca00d88433052b58fdae4e4ccdd12c53c458f1ce1d69'
 assert digest(area+'linux-sys-v6.12.c') == primary['sha256']!.str() && digest(primary['cached_source']!.str()) == primary['sha256']!.str()
 for path in ['states/p1-before-arm/groupzombie','states/p1-after-arm/groupzombie','states/p1-after-arm/runtime','states/p1-after-arm/grouporder','states/p1-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+path+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 for name in ['sdk-inputs.json','primary-reuse.json','lifetime-review.txt'] {publish(area+name,out+'groupzombie-'+name)!}
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
 mut slabs := [4]int{}; mut pages := [4]int{}; mut seen := map[string]bool{}
 for row in log.split_into_lines().filter(it.starts_with('LINUX GROUPZOMBIE SLAB:') || it.starts_with('LINUX GROUPZOMBIE STORAGE:')) {
  fields := row.fields(); assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
  ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); assert ordinary in [0,1] && namespace in [0,1]
  cohort := ordinary+2*namespace; pair := fields[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
  if fields[2] == 'SLAB:' {
   assert fields[5].starts_with('size=') && fields[7] == 'cycles=200'; key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true; slabs[cohort]++
  } else { assert fields[5] == 'cycles=200' && fields[7] == 'PASS' && pair[0].u64() > 0; pages[cohort]++ }
 }
 for cohort in 0 .. 4 {
  assert slabs[cohort] == if phase == 'before' {0} else if arch == 'aarch64' {18} else {14}
  assert pages[cohort] == if phase == 'before' {0} else {1}
 }
}

fn failure(log string, arch string) {
	assert log.contains('LINUX GROUPZOMBIE DETAIL:'), 'groupzombie baseline failure markers required'
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
		'wrapper_source':    state + '/source/groupzombiereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/groupzombie-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/groupzombiereferenceinit/core.v')
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
		assert false, 'groupzombie assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: groupzombie-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'groupzombie assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'groupzombie baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in set_process_group; exit_published under the existing table lock admits completed zombie targets and group members, preserving incomplete-teardown exclusion and existing ownership/notifications; no added allocation/pin/free or compiler normalization; post-exit mutation lifetime independently reviewed\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'a6046ead7309dad8e166b94e819fd9726ac4eec7'
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
		assert path.starts_with(states + 'p1-before-arm/') || path.starts_with(states + 'p1-before-x86/') || path.starts_with(states + 'p1-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['groupzombie']
			} else {
				['groupzombie', 'runtime', 'grouporder']
			}
			for name in names {
				probe := states + 'p1-' + phase + '-' + suffix + '/' + name
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
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/proc/job_groups.v'
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 66
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 66
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
			if path in ['kernel/proc/job_groups.v'] {
				assert before_inputs[path] == digest(area+'before-'+os.file_name(path))
				assert git(tree,['show',base+':'+path])!.trim_space() == os.read_file(area+'before-'+os.file_name(path))!.trim_space()
			} else { assert before_inputs[path] == hash }
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/proc/job_groups.v')
			'kernel_source_before':     digest(area + 'before-job_groups.v')
			'fixture_source':           digest(root + 'tests/linux-compat/groupzombiefixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-sys-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'lifetime_review': digest(area + 'lifetime-review.txt')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/grouporder-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'primary_reuse': digest(area + 'primary-reuse.json')
			'scope_contract': digest(area + 'scope-check.log')
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
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['groupzombie']
			} else {
				['groupzombie', 'runtime', 'grouporder']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['groupzombie_source', 'groupzombie_init', 'groupzombie_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/groupzombie/serial.log')!
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
				'native':    state + '/groupzombie/serial.log'
				'build':     build
			} {
				publish(path, out + 'groupzombie-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'groupzombie' { continue }
					publish(state + '/' + name + '/serial.log', out + 'groupzombie-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p1-before-' + suffix + '/groupzombie'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 5
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['groupzombie_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'groupzombie-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'groupzombie-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native completed-zombie setpgid targets and zombie-only destination groups,17152 controls per architecture across root/UID1000 initial and one-level PID namespaces. Four WNOWAIT/pidfd-POLLIN confirmed zombies: unexecuted/exec same-session and unexecuted/exec detached-session, plus one live direct child. Each zombie has448 raw/musl setter controls;512 live-destination checks before/after reaping;1984 queries/reaped-target controls. Original5376 failures; corrected and identical-ELF Linux6.12.51 zero. Real zombie group mutations and restoration, P_PGID WNOWAIT/ECHILD observation, live joins/restoration leaving the zombie as sole group member for every attempt, exact EINVAL/EACCES/EPERM/ESRCH, eight actual exec-entry receipts,16 exit/readiness and16 reaping edges. Four warmed200-cycle cohorts alternate raw-upper-word and genuine musl mutations, joins and errors with flat slabs/pages. Four production builds, runtime/grouporder regressions, unchanged allocation diagnostics,2014 SDK inputs,15146 V compiler inputs,66 semantic inputs, exact one-function C scope, independent post-exit lifetime review and executing audit negatives. Both eligibility guards retain incomplete-teardown ESRCH exclusion via table-locked exit_published. Concurrent teardown/reap/credentials, zombie descendants, non-parent mutations, retained groups after leader reap, nested/cross-namespace views, MAC policy, terminal signals, PID reuse, GNU/translated/ELF32 paths and three broad roadmap gates remain separate.'
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
		publish(area + name, out + 'groupzombie-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'groupzombie-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native groupzombie conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'groupzombie-audit.log')!
	println('Native groupzombie conformance audit: PASS')
}
