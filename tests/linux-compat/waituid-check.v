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
 rows := log.split_into_lines().filter(it.starts_with('LINUX WAITUID TOPOLOGY:')); assert rows.len == 32
 mut seen := map[string]bool{}
 for row in rows {
  fields := row.fields(); assert fields.len == 12
  assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
  assert fields[5] in ['profile=0','profile=1','profile=2','profile=3'] && fields[6] in ['killed=0','killed=1']
  key := fields[3]+fields[4]+fields[5]+fields[6]; assert key !in seen; seen[key] = true
  for index,prefix in {7:'self=',8:'pid=',9:'real=',10:'effective=',11:'saved='} {assert fields[index].starts_with(prefix)}
  self := fields[7].all_after('=').int(); pid := fields[8].all_after('=').int(); assert self > 1 && pid > 1 && pid != self
  if fields[4] == 'namespace=1' {assert self == 2}
  profile := fields[5].all_after('=').int(); ordinary := fields[3] == 'ordinary=1'
  assert fields[9] == 'real='+if ordinary {'1000'} else {['0','1001','0','4294967294']![profile]}
  assert fields[10] == 'effective='+if ordinary {if profile%2 == 0 {'1000'} else {'1002'}} else {['0','0','1003','1004']![profile]}
  assert fields[11] == 'saved='+if ordinary {'1002'} else {['0','1002','0','0']![profile]}
 }
 mut cases := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  outcomes := log.split_into_lines().filter(it.starts_with('LINUX WAITUID '+label)); assert outcomes.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in outcomes {
   fields := row.fields(); assert fields.len == 8
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1'] && fields[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true
   assert fields[6].starts_with('calls=') && fields[7].starts_with('failures=')
   kind := fields[5].all_after('=').int(); n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
   assert n == [772,772,772,772,16,384]![kind]
   assert f == if phase == 'before' && kind < 4 {if fields[3] == 'ordinary=0' {386} else {772}} else {0}
   if label == 'CASES:' {cases[key] = fields[6]+fields[7]} else {assert cases[key] == fields[6]+fields[7]}
   calls += n; failures += f
  }
  assert calls == 13952 && failures == if phase == 'before' {9264} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX WAITUID DETAIL:') && log.contains('LINUX WAITUID FAIL:') && !log.contains('LINUX WAITUID: PASS')}
 else {assert !log.contains('LINUX WAITUID DETAIL:') && !log.contains('LINUX WAITUID FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX WAITUID REFERENCE: PASS') && !log.contains('LINUX WAITUID STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX WAITUID: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 old := '\tchild := change.child\n\tstatus := change.status\n'
 new := '\tchild := change.child\n\t// Credentials can change while a stopped/continued child remains alive.\n\t// Copy its real UID under the credential lock; the wait claim already pins it.\n\tproc.lock_table()\n\tuid := child.uid\n\tproc.unlock_table()\n\tstatus := change.status\n'
 assert before.count(old) == 1 && before.count('\t\tsi_status: i32((status >> 8) & 0xff)') == 1
 expected := before.replace(old,new).replace('\t\tsi_status: i32((status >> 8) & 0xff)','\t\tsi_uid:    uid\n\t\tsi_status: i32((status >> 8) & 0xff)')
 assert after == expected && before != after,'Only waitid real-UID snapshot/output changes; copyout, claims, pins and ownership remain identical'
 assert digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
}

fn body(source string,name string) string {
 rows := source.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with('{'))
 assert rows.len == 1,name
 return definition(source,'\n'+rows[0])
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'userland__syscall_waitid'); new := body(after,'userland__syscall_waitid')
 assert old != new
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','finish_child_change(','copy_to_user('] {assert old.count(token) == new.count(token),token}
 assert new.contains('uid = child->uid') && new.contains('.si_uid = uid')
 assert new.count('proc__lock_table()') == old.count('proc__lock_table()')+1 && new.count('proc__unlock_table()') == old.count('proc__unlock_table()')+1
 assert before.replace(old,'') == after.replace(new,''),'Whole production C differs outside waitid; no normalization'
}

fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; assert sdk.len == 2014
 prior := object('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')!; assert sdk.len == prior.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 primary := object(area+'primary-reuse.json')!
 assert primary['source_url']!.str() == 'https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/exit.c'
 assert primary['sha256']!.str() == '7c28bfc644117470b9cbe6d46c84580de98225755bbb227e61d638ea7104025d'
 assert digest(area+'linux-exit-v6.12.c') == primary['sha256']!.str() && digest(primary['cached_source']!.str()) == primary['sha256']!.str()
 for path in ['states/p1-before-arm/waituid','states/p2-after-arm/waituid','states/p2-after-arm/runtime','states/p2-after-arm/waitempty','states/p1-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+path+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 for name in ['sdk-inputs.json','primary-reuse.json','primary-source-note.txt','initial-helper-refusal.log','initial-helper-source.v'] {publish(area+name,out+'waituid-'+name)!}
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
 for row in log.split_into_lines().filter(it.starts_with('LINUX WAITUID SLAB:') || it.starts_with('LINUX WAITUID STORAGE:')) {
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
	assert log.contains('LINUX WAITUID DETAIL:'), 'waituid baseline failure markers required'
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
		'wrapper_source':    state + '/source/waituidreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/waituid-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/waituidreferenceinit/core.v')
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

// A host reboot interrupted the first corrected run after two passing cases.
// Keep its partial receipt and complete artifacts; missing serial output for
// the third case never counts as a guest verdict.
fn interrupted(area string,out string) ! {
 assert os.read_file(area+'host-reboot.txt')!.contains('sec = 1792077859')
 pins := object(area+'interrupted-watch-retained-inputs.json')!
 assert pins.len == 63
 for path,hash in pins {assert path.starts_with(area+'states/p1-') && os.inode(path).typ == .regular && digest(path) == hash.str()}
 assert os.read_file(area+'interrupted-watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 6
 mut captured := map[string]string{}
 restoration := object(area+'kernel-restoration.json')!
 assert restoration.keys().sorted() == ['arm-after','x86-after']
 for arch,suffix in {'aarch64':'arm','x86_64':'x86'} {
  state := area+'states/p1-after-'+suffix
  final := area+'states/p2-after-'+suffix
  value := object(state+'/receipt.json')!
  assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == digest(final+'/kernel/bin/vinix') && digest(state+'/kernel/bin/vinix') == digest(final+'/kernel/bin/vinix')
  repair := restoration[suffix+'-after']!.as_map_of_strings()
  assert repair['working_file'] == area+'kernel-'+suffix+'/kernel/bin/vinix' && repair['snapshot'] == state+'/kernel/bin/vinix'
  assert repair['restored_sha256'] == value['kernel_sha256']!.str() && digest(repair['working_file']) == repair['restored_sha256'] && digest(repair['snapshot']) == repair['restored_sha256']
  assert repair['damaged_copy'] == area+'post-reboot-after-'+suffix+'-kernel' && digest(repair['damaged_copy']) == repair['damaged_sha256'] && repair['damaged_sha256'] != repair['restored_sha256']
  damaged := os.read_bytes(repair['damaged_copy'])!; frozen := os.read_bytes(repair['snapshot'])!
  assert damaged.len == frozen.len && damaged[..64].hex() == repair['damaged_header'] && damaged[..64].all(it == 0) && frozen[..64].hex() == repair['restored_header'] && frozen[..6] == [u8(127),`E`,`L`,`F`,2,1]
  captured[repair['damaged_copy']] = repair['damaged_sha256']
  assert os.read_file(area+'post-reboot-'+suffix+'-refusal.log')!.trim_space() == 'kernel must be a matching little-endian ELF64'
  refused := os.read_file(area+'post-reboot-'+suffix+'-producer.log')!
  assert refused.contains('code = 2') && refused.contains('kernel must be a matching little-endian ELF64')
  for name in ['post-reboot-'+suffix+'-refusal.log','post-reboot-'+suffix+'-producer.log'] {captured[area+name] = digest(area+name); publish(area+name,out+'waituid-'+name)!}
  entries := value['results']!.as_array(); assert entries.len == 2
  for index,row in entries {
   entry := row.as_map(); name := ['waituid','runtime']![index]
   assert entry['name']!.str() == name && entry['exit_code']!.int() == 0 && entry['detail']!.str() == ''
   assert entry['source_sha256']!.str() == digest(state+'/sources/'+name+'fixture/core.v') && entry['init_sha256']!.str() == digest(state+'/'+name+'/init') && entry['iso_sha256']!.str() == digest(state+'/'+name+'/test.iso')
   assert os.read_file(state+'/'+name+'/serial.log')!.contains('LINUX '+name.to_upper()+': PASS')
   publish(state+'/'+name+'/serial.log',out+'waituid-interrupted-'+arch+'-'+name+'.log')!
  }
  semantics(os.read_file(state+'/waituid/serial.log')!,'after',arch,false)
  storage(os.read_file(state+'/waituid/serial.log')!,arch,'after')
  assert !os.exists(state+'/waitempty/serial.log') && !os.exists(state+'.log')
  producer := area+'final-native-'+suffix+'-after-producer.log'
  assert os.read_file(producer)! == ''; captured[producer] = digest(producer)
  for name in ['waituid','runtime','waitempty'] {
   for artifact in ['init','fixture.c'] {assert digest(state+'/'+name+'/'+artifact) == digest(final+'/'+name+'/'+artifact)}
   assert digest(state+'/sources/'+name+'fixture/core.v') == digest(final+'/sources/'+name+'fixture/core.v')
   if suffix == 'arm' {for artifact in ['init','fixture.o','serial.o'] {
    driver := object(state+'/'+name+'/'+artifact+'.compiler.json')!
    assert driver['status']!.str() == '0' && driver['output']!.str() == '' && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
   }}
  }
  // Preserve all regular files, including the incomplete boot's disposable
  // staging. Only completed final profiles are retired by the watcher.
  for path in os.walk_ext(state,'') {if os.inode(path).typ == .regular {captured[path] = digest(path)}}
  publish(state+'/receipt.json',out+'waituid-interrupted-'+arch+'-receipt.json')!
 }
 for name in ['kernel-restoration.json','restore-kernels.v','restore-kernels','host-reboot.txt','interrupted-watch.log','interrupted-watch-retained-inputs.json','interrupted-watch.v','interrupted-watch'] {captured[area+name] = digest(area+name)}
 os.write_file(area+'interrupted-inputs.json',json2.encode(captured,prettify:true)+'\n')!
 for name in ['kernel-restoration.json','host-reboot.txt','interrupted-watch.log','interrupted-watch-retained-inputs.json','interrupted-inputs.json'] {publish(area+name,out+'waituid-'+name)!}
}

fn main() {
	if '--scope-only' in os.args {
		area := os.args[2].trim_right('/')+'/'
		check_source(area,'/Users/alex/code/vinix/')!
		for suffix in ['arm','x86'] {check_c(area,suffix)!}
		println('Native waitid child-UID source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'waituid assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: waituid-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	interrupted(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'waituid assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'waituid baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in waitid: snapshot child real UID under the credential table lock, release it before copyout, set si_uid; existing wait claim pins the child; copyout, event consumption, claims, pins, ownership, allocations and frees unchanged; no normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'b3d1ebcb8ea58a266d09982db5f525bbd445593a'
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
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-exit-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/exit.c'
	linux_source := os.read_file(area + 'linux-exit-v6.12.c')!
	assert linux_source.contains('SYSCALL_DEFINE5(waitid, int, which, pid_t, upid') && linux_source.contains('SYSCALL_DEFINE4(wait4, pid_t, upid') && linux_source.contains('if (upid == INT_MIN)')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-arm/') || path.starts_with(states + 'p1-before-x86/') || path.starts_with(states + 'p2-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['waituid']
			} else {
				['waituid', 'runtime', 'waitempty']
			}
			for name in names {
				probe := states + if phase == 'before' { 'p1-' } else { 'p2-' } + phase + '-' + suffix + '/' + name
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
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/userland/linux_task.v'
		// Bind the changed wait source to the committed base and both productions.
		assert git(tree,['show',base+':kernel/userland/linux_task.v'])!.trim_space() == os.read_file(area+'before-linux_task.v')!.trim_space()
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 67
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 67
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
			if path in ['kernel/userland/linux_task.v'] {
				assert before_inputs[path] == digest(area+'before-'+os.file_name(path))
				assert git(tree,['show',base+':'+path])!.trim_space() == os.read_file(area+'before-'+os.file_name(path))!.trim_space()
			} else { assert before_inputs[path] == hash }
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/userland/linux_task.v')
			'kernel_source_before':     digest(area + 'before-linux_task.v')
			'fixture_source':           digest(root + 'tests/linux-compat/waituidfixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-exit-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'primary_source_note': digest(area + 'primary-source-note.txt')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'primary_reuse': digest(area + 'primary-reuse.json')
			'scope_contract': digest(area + 'scope-check.log'), 'initial_helper_refusal':digest(area+'initial-helper-refusal.log'), 'initial_helper_source':digest(area+'initial-helper-source.v')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-retained-inputs.json')
			'watch_log':                digest(area + 'watch.log'), 'host_reboot':digest(area+'host-reboot.txt'), 'interrupted_inputs':digest(area+'interrupted-inputs.json')
		}
		for name in ['manage.v', 'manage', 'watch.v', 'watch', 'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + if phase == 'before' { 'p1-' } else { 'p2-' } + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['waituid']
			} else {
				['waituid', 'runtime', 'waitempty']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['waituid_source', 'waituid_init', 'waituid_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/waituid/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + if phase == 'before' { 'initial-build-' + suffix + '-before.log' } else { 'build-' + suffix + '-after-producer.log' }
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/waituid/serial.log'
				'build':     build
			} {
				publish(path, out + 'waituid-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'waituid' { continue }
					publish(state + '/' + name + '/serial.log', out + 'waituid-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p1-before-' + suffix + '/waituid'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 5
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['waituid_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'waituid-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'waituid-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native waitid child real UID: 13952 controls per architecture, original9264 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts, four credential profiles per cohort including real/effective/saved differences and UID4294967294. Stopped, continued, exit37 and SIGKILL; three selectors, eight raw/musl forms, aligned/unaligned output, NULL/valid rusage, WNOWAIT repeats, consuming event and cleared no-event/ECHILD, NULL infop. Four warmed200-cycle cohorts with flat storage, four production builds, runtime/waitempty regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler inputs, exact one-function whole-C scope and executing audit negatives. Initial host helper compile refusal retained separately; no guest or build ran on it. A host reboot interrupted p1 corrected runs after passing UID/runtime cases, before waitempty produced a verdict. Those partial profiles and all regular files remain pinned; complete corrected p2 profiles rerun all three cases against unchanged production kernels. Successful-event padding/accounting, consuming copyout faults, mapped user IDs, credential-change races, P_PIDFD, __W flags, ptrace, interrupted/restarted waits, GNU/foreign ABIs and broad roadmap gates remain separate.'
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
		publish(area + name, out + 'waituid-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'waituid-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native waituid conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'waituid-audit.log')!
	println('Native waituid conformance audit: PASS')
}
