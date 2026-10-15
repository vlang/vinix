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
 rows := log.split_into_lines().filter(it.starts_with('LINUX WAITABI TOPOLOGY:')); assert rows.len == 8
 mut seen := map[string]bool{}; mut ids := map[string]bool{}; mut targets := map[string]string{}
 for row in rows {
  fields := row.fields(); assert fields.len == 11
  assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
  assert fields[5] == if fields[3] == 'ordinary=0' {'uid=0'} else {'uid=1000'}
  for index,prefix in {6:'self=',7:'kind=',8:'pid=',9:'group=',10:'session='} {assert fields[index].starts_with(prefix)}
  self := fields[6].all_after('=').int(); kind := fields[7].all_after('=').int(); pid := fields[8].all_after('=').int(); assert self > 1 && kind in [0,1] && pid > 1 && pid != self
  if fields[4] == 'namespace=1' {assert self == 2}
  cohort := fields[3]+fields[4]; key := cohort+fields[7]; assert key !in seen; seen[key] = true; targets[key] = fields[8]
  id_key := cohort+fields[8]; assert id_key !in ids; ids[id_key] = true
  assert fields[9].all_after('=').int() == if kind == 0 {pid} else {self}
  assert fields[10].all_after('=').int() == self
 }
 for label in ['EXIT:','REAP:'] {
  edges := log.split_into_lines().filter(it.starts_with('LINUX WAITABI '+label)); assert edges.len == 4; seen.clear()
  for row in edges {
   fields := row.fields(); assert fields.len == if label == 'EXIT:' {8} else {7}
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
   key := fields[3]+fields[4]+'kind=0'; assert key !in seen && targets[key] == fields[5]; seen[key] = true
   if label == 'EXIT:' {assert fields[6] == 'wait=CLD_EXITED' && fields[7] == 'status=37'} else {assert fields[6] == 'status=37'}
  }
 }
 mut cases := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  outcomes := log.split_into_lines().filter(it.starts_with('LINUX WAITABI '+label)); assert outcomes.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in outcomes {
   fields := row.fields(); assert fields.len == 8
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1'] && fields[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true
   assert fields[6].starts_with('calls=') && fields[7].starts_with('failures=')
   kind := fields[5].all_after('=').int(); n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
   assert n == [1152,576,8704,8704,8704,1728]![kind]
   assert f == if phase == 'before' {[948,0,5155,0,5155,1605]![kind]} else {0}
   if label == 'CASES:' {cases[key] = fields[6]+fields[7]} else {assert cases[key] == fields[6]+fields[7]}
   calls += n; failures += f
  }
  assert calls == 118272 && failures == if phase == 'before' {51452} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX WAITABI DETAIL:') && log.contains('LINUX WAITABI FAIL:') && !log.contains('LINUX WAITABI: PASS')}
 else {assert !log.contains('LINUX WAITABI DETAIL:') && !log.contains('LINUX WAITABI FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX WAITABI REFERENCE: PASS') && !log.contains('LINUX WAITABI STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX WAITABI: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 expected := before.replace('pub fn syscall_wait4(_ voidptr, pid int, status_ptr u64, options int, rusage_ptr u64) (u64, u64) {',
  'pub fn syscall_wait4(_ voidptr, pid_word u64, status_ptr u64, options_word u64, rusage_ptr u64) (u64, u64) {\n\t// Linux imports pid_t and int from the low 32 bits of each register.\n\tpid := int(i32(pid_word))\n\toptions := int(i32(options_word))')
  .replace('change := take_child_change(mut current_process, pid, options | wexited)',
  '// Its negation is undefined in Linux\'s signed pid_t. Invalid options take\n\t// precedence, then this selector returns ESRCH instead of scanning children.\n\tif pid == -2147483648 { return errno.err, errno.esrch }\n\tchange := take_child_change(mut current_process, pid, options | wexited)')
  .replace('pub fn syscall_waitid(_ voidptr, idtype int, id u64, infop u64, options int, rusage_ptr u64) (u64, u64) {',
  'pub fn syscall_waitid(_ voidptr, idtype_word u64, id_word u64, infop u64, options_word u64, rusage_ptr u64) (u64, u64) {\n\tidtype := int(i32(idtype_word))\n\tid := u64(u32(id_word))\n\toptions := int(i32(options_word))')
 exact := after == expected && after != before; assert exact,'Only native wait scalar imports and the INT_MIN selector error change'
 assert digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
}

fn body(source string,name string) string {
 rows := source.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with('{'))
 assert rows.len == 1,name
 return definition(source,'\n'+rows[0])
}
fn check_c(area string,suffix string) ! {
 mut before := os.read_file(area+'before-'+suffix+'.c')!; mut after := os.read_file(area+'after-'+suffix+'.c')!
 for name in ['userland__syscall_wait4','userland__syscall_waitid'] {
  old := body(before,name); new := body(after,name); assert old != new
  for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_thread(','unpin_thread('] {assert old.count(token) == new.count(token),token}
  before = before.replace(old,''); after = after.replace(new,'')
  old_decl := before.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with(';')); new_decl := after.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with(';')); assert old_decl.len == 1 && new_decl.len == 1
  before = before.replace(old_decl[0],''); after = after.replace(new_decl[0],'')
 }
 unchanged := before == after; assert unchanged,'Whole production C differs outside wait4/waitid definitions and their exact declarations; no normalization'
}

fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; assert sdk.len == 2014
 prior := object('/Users/alex/.cache/vinix-linux-compat/groupzombie-20261015/sdk-inputs.json')!; assert sdk.len == prior.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 primary := object(area+'primary-reuse.json')!
 assert primary['source_url']!.str() == 'https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/exit.c'
 assert primary['sha256']!.str() == '7c28bfc644117470b9cbe6d46c84580de98225755bbb227e61d638ea7104025d'
 assert digest(area+'linux-exit-v6.12.c') == primary['sha256']!.str() && digest(primary['cached_source']!.str()) == primary['sha256']!.str()
 for path in ['states/p2-before-arm/waitabi','states/p2-after-arm/waitabi','states/p2-after-arm/runtime','states/p2-after-arm/groupzombie','states/p3-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+path+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 for name in ['sdk-inputs.json','primary-reuse.json','primary-source-note.txt'] {publish(area+name,out+'waitabi-'+name)!}
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
 for row in log.split_into_lines().filter(it.starts_with('LINUX WAITABI SLAB:') || it.starts_with('LINUX WAITABI STORAGE:')) {
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
	assert log.contains('LINUX WAITABI DETAIL:'), 'waitabi baseline failure markers required'
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
		'wrapper_source':    state + '/source/waitabireferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/waitabi-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/waitabireferenceinit/core.v')
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

fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 old_source := area+'states/p1-before-arm/sources/waitabifixture/core.v'
 assert digest(old_source) == digest(area+'states/p1-before-x86/sources/waitabifixture/core.v')
 assert digest(old_source) != digest('/Users/alex/code/vinix/tests/linux-compat/waitabifixture/core.v')
 old := os.read_file(old_source)!
 assert old.contains('if code != 0 {untouched(&info,sizeof(C.siginfo_t))}')
 assert old.contains('actual.ret == -1 && actual.code == C.EFAULT && ready(state) && (target == 0 || status == 37<<8)')
 publish(old_source,out+'waitabi-diagnostic-probe.v')!
 for suffix in ['arm','x86'] {
  native := area+'states/p1-before-'+suffix; reference := area+'states/p1-reference-'+suffix
  assert digest(native+'/waitabi/init') == digest(reference+'/probe')
  receipt := object(reference+'/receipt.json')!; assert !receipt['passed']!.bool() && receipt['finished']!.bool() && !receipt['forced']!.bool()
  assert receipt['artifacts']!.as_map_of_strings()['probe'] == digest(reference+'/probe')
  log := os.read_file(reference+'/serial.log')!
  assert log.contains('LINUX WAITABI DETAIL: kind=2') && log.contains('LINUX WAITABI DETAIL: kind=3') && log.contains('LINUX WAITABI FAIL: setup stage=8 errno=10') && log.contains('Kernel panic - not syncing: Attempted to kill init!')
  for path in os.walk_ext(native,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
  for path in os.walk_ext(reference,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
  for path in [native+'.log',reference+'.log'] {pins[path] = digest(path)}
  for label,path in {'native-serial.log':native+'/waitabi/serial.log','native-receipt.json':native+'/receipt.json','linux-serial.log':reference+'/serial.log','linux-receipt.json':reference+'/receipt.json'} {
   publish(path,out+'waitabi-diagnostic-'+suffix+'-'+label)!
  }
 }
 assert pins.len == 58
 pins[area+'reference-controller-initial.v'] = digest(area+'reference-controller-initial.v')
 for suffix in ['arm','x86'] {
  state := area+'states/p2-reference-'+suffix
  refused := object(state+'/receipt.json')!
  assert !refused['passed']!.bool() && refused['finished']!.bool() && refused['forced']!.bool() && refused['status']!.int() == 0
  assert refused['artifacts']!.as_map_of_strings()['controller_source'] == pins[area+'reference-controller-initial.v']
  log := os.read_file(state+'/serial.log')!
  semantics(log,'after',if suffix == 'arm' {'aarch64'} else {'x86_64'},true)
  assert os.read_file(state+'.log')!.contains('Unexpected reference case count')
  for path in os.walk_ext(state,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
  pins[state+'.log'] = digest(state+'.log')
  publish(state+'/receipt.json',out+'waitabi-controller-refusal-'+suffix+'-receipt.json')!
  publish(state+'.log',out+'waitabi-controller-refusal-'+suffix+'.log')!
 }
 audit_failure := os.read_file(area+'audit-producer-first.log')!
 assert audit_failure.contains('assert pins.len > 60') && audit_failure.contains('pins.len = 58') && os.read_file(area+'audit-producer-first.log.status')!.trim_space() == '1'
 for name in ['audit-initial.v','audit-initial','audit-producer-first.log','audit-producer-first.log.status'] {pins[area+name] = digest(area+name)}
 publish(area+'reference-controller-initial.v',out+'waitabi-controller-initial.v')!
 publish(area+'audit-initial.v',out+'waitabi-audit-initial.v')!
 publish(area+'audit-producer-first.log',out+'waitabi-audit-initial-refusal.log')!
 os.write_file(area+'diagnostic-inputs.json',json2.encode(pins,prettify:true)+'\n')!
 publish(area+'diagnostic-inputs.json',out+'waitabi-diagnostic-inputs.json')!
 note := 'The first probe incorrectly required unchanged waitid siginfo on errors and preservation of a zombie after wait4 copyout failure. Linux v6.12 instead writes the siginfo fields on these errors and consumes an exited child before wait4 status/rusage copyout. Both identical-ELF Linux references therefore failed, reached the expected ECHILD setup refusal at the later reap, and panicked on PID1 exit. These full original source/C/ELF/receipts/serial profiles remain pinned. Final p2 controls compare successful siginfo output plus exact selector/option errors, use held-child wait4 output faults (no event, no copyout), and require retention only for WNOWAIT waitid. Error siginfo copyout and consuming wait4 copy faults are published unsupported semantics, not silently treated as passing. Final sources/C/ELFs are independently equal across original/fixed/Linux.\n'
 os.write_file(area+'diagnostic-note.txt',note)!
 publish(area+'diagnostic-note.txt',out+'waitabi-diagnostic-note.txt')!
 more := 'The p2 Linux probe checks all pass, but the controller retained the previous fixture counts and explicitly rejects both receipts with Unexpected reference case count. The corrected controller boots the same unchanged probe again in p3; no receipt was relabeled. The first audit also refused an incorrect >60 diagnostic-file estimate: the complete original walk contains58 regular files, now checked exactly. Both controller and audit source/binary/log/status artifacts remain pinned; final verification must pass separately.\n'
 os.write_file(area+'controller-audit-refusal-note.txt',more)!
 publish(area+'controller-audit-refusal-note.txt',out+'waitabi-controller-audit-refusal-note.txt')!
}

fn main() {
	if '--scope-only' in os.args {
		area := os.args[2].trim_right('/')+'/'
		check_source(area,'/Users/alex/code/vinix/')!
		for suffix in ['arm','x86'] {check_c(area,suffix)!}
		println('Native wait ABI source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'waitabi assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: waitabi-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'waitabi assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p3-reference-arm/serial.log', 'aarch64'], 'waitabi baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in native wait4/waitid definitions and exact declarations; low32 scalar imports and INT_MIN ESRCH after options validation; existing child claims, pins, locks, copyout and notifications unchanged; no added allocation/free/pin or compiler normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '6fb03bb2e396a18b64d8795e80be39b660945f59'
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
		assert path.starts_with(states + 'p2-before-arm/') || path.starts_with(states + 'p2-before-x86/') || path.starts_with(states + 'p2-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['waitabi']
			} else {
				['waitabi', 'runtime', 'groupzombie']
			}
			for name in names {
				probe := states + 'p2-' + phase + '-' + suffix + '/' + name
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
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 66
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 66
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
			'fixture_source':           digest(root + 'tests/linux-compat/waitabifixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-exit-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'primary_source_note': digest(area + 'primary-source-note.txt')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/groupzombie-20261015/sdk-inputs.json')
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
			state := states + 'p2-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['waitabi']
			} else {
				['waitabi', 'runtime', 'groupzombie']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['waitabi_source', 'waitabi_init', 'waitabi_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/waitabi/serial.log')!
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
				'native':    state + '/waitabi/serial.log'
				'build':     build
			} {
				publish(path, out + 'waitabi-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'waitabi' { continue }
					publish(state + '/' + name + '/serial.log', out + 'waitabi-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p2-before-' + suffix + '/waitabi'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 5
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p3-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['waitabi_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'waitabi-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'waitabi-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native Linux wait4/waitid low32 scalar imports and INT_MIN ESRCH after option validation. 118272 controls per architecture across root/UID1000 initial and one-level PID namespaces; original51452 failures, corrected and identical-ELF Linux6.12.51 zero. Two held direct children in distinct groups; one then exits status37. Eight raw/musl argument forms independently span pid/options and which/id/options. Live nohang output/rusage sentinels, zombie WNOWAIT selection, EINVAL/ECHILD/ESRCH/EFAULT precedence, held-child wait4 ignores invalid outputs; WNOWAIT waitid copy faults retain the zombie and post-reap errors. Four warmed200-cycle cohorts, flat storage; four production builds and runtime/groupzombie regressions. Full compiler/SDK/input/artifact pins, unchanged allocation diagnostics, exact two-function C scope and executing audit negatives. No waiter lifetime changes. GNU/translated/ELF32 paths, P_PIDFD, __W flags, cross-thread/ptrace waits, waitid error copyout and wait4 consumption after copyout failure, si_uid/accounting, concurrent child/group/reap changes, signal restart and three broad roadmap gates remain separate.'
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
		publish(area + name, out + 'waitabi-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'waitabi-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native waitabi conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'waitabi-audit.log')!
	println('Native waitabi conformance audit: PASS')
}
