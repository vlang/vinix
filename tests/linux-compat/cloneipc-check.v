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
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

struct Evidence {
	architecture  string
	context       string
	base_commit   string
	artifacts     map[string]string
	source_inputs map[string]string
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

fn storage(log string, arch string, _phase string) {
	mut slabs := [4]int{}
	mut pages := [4]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC SLAB:') || it.starts_with('LINUX CLONEIPC STORAGE:')) {
		fields := row.fields()
		assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
		ordinary := fields[3].all_after('=').int()
		namespace := fields[4].all_after('=').int()
		assert ordinary in [0, 1] && namespace in [0, 1]
		cohort := ordinary + 2 * namespace
		pair := fields[6].all_after('=').split('/')
		assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' {
			assert fields[5].starts_with('size=') && fields[7] == 'cycles=200'
			key := fields[3] + fields[4] + fields[5]
			assert key !in seen
			seen[key] = true
			slabs[cohort]++
		} else {
			assert fields[5] == 'cycles=200' && fields[7] == 'PASS' && pair[0].u64() > 0
			pages[cohort]++
		}
	}
	for cohort in 0 .. 4 {
		assert slabs[cohort] == if arch == 'aarch64' {
			18
		} else {
			14
		}
		assert pages[cohort] == 1
	}
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
		'wrapper_source':    state + '/source/cloneipcreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/cloneipc-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/cloneipcreferenceinit/core.v')
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

fn original_errors(log string) {
 rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC DETAIL:'))
 assert rows.len==48
 mut seen:=map[string]bool{}
 for row in rows {
  f:=row.fields()
  assert f.len==12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  assert f[5] in ['kind=0','kind=1','kind=2','kind=4']
  key:=f[3]+f[4]+f[5]+f[6];assert key !in seen;seen[key]=true
  if f[5]=='kind=4' {
   assert f[6] in ['index=33','index=34','index=35'] && f[7..]==['result=-1','errno=95','expected=1','guarded=1','child=0']
  } else {
   assert f[6] in ['index=0','index=1','index=2']
   if f[5]=='kind=2' {
    assert f[7].starts_with('result=') && f[7].all_after('=').int()>1
    assert f[8..]==['errno=0','expected=22','guarded=1','child=1']
   } else {assert f[7..]==['result=-1','errno=9','expected=22','guarded=1','child=0']}
  }
 }
}

fn failure(log string, arch string) {
	assert log.contains('LINUX CLONEIPC DETAIL:'), 'cloneipc baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn descriptors(log string) {
 rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC FD:'))
 assert rows.len==4
 mut seen:=map[string]bool{}
 for row in rows {
  f:=row.fields()
  assert f.len==6 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  assert f[5].starts_with('wrong=') && f[5].all_after('=').int()>=0
  key:=f[3]+f[4];assert key !in seen;seen[key]=true
 }
}

fn queue_canary(log string) {
 starts:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC QUEUE:'))
 ends:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC QUEUEREMOVED:'))
 assert starts.len==4 && ends.len==4
 mut ids:=map[string]string{}
 for row in starts {
  f:=row.fields();assert f.len==7 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  assert f[5].starts_with('id=') && f[5].all_after('=').int()>=0 && f[6]=='mode=0600'
  key:=f[3]+f[4];assert key !in ids;ids[key]=f[5]
 }
 mut seen:=map[string]bool{}
 for row in ends {
  f:=row.fields();assert f.len==8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key:=f[3]+f[4];assert key in ids && key !in seen;seen[key]=true
  assert f[5]==ids[key] && f[6..]==['removed=1','ipc_unchanged=1']
 }
}

fn capabilities(log string) {
 for label in ['CAPS:','CAPSRESTORED:'] {
  rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC '+label))
  assert rows.len==4
  mut seen:=map[string]bool{}
  for row in rows {
   f:=row.fields()
   assert f.len==if label=='CAPS:' {8} else {6}
   assert f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5]=='sysadmin=0'
   if label=='CAPS:' {assert f[6..]==['permitted_sysadmin=1','keepcaps=1']}
   key:=f[3]+f[4];assert key !in seen;seen[key]=true
  }
 }
}

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	capabilities(log)
	queue_canary(log)
	descriptors(log)
	mut seen := map[string]bool{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC ' + label))
		assert rows.len == 24
		seen.clear()
		mut total := 0
		mut failures := 0
		for row in rows {
			f := row.fields()
			assert f.len == 8 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
				'namespace=0',
				'namespace=1',
			] && f[5] in ['kind=0', 'kind=1', 'kind=2', 'kind=3', 'kind=4', 'kind=5']
			key := label + f[3] + f[4] + f[5]
			assert key !in seen
			seen[key] = true
			class := f[5].all_after('=').int()
			calls := [96, 96, 108, 60, 72, 36]![class]
			bad := if phase == 'after' {0} else if class in [0,1] {calls} else if class==2 {96} else if class==4 {15} else {0}
			assert f[6] == 'calls=' + calls.str() && f[7] == 'failures=' + bad.str()
			total += calls
			failures += bad
		}
		assert total == 1872 && failures == if phase == 'after' { 0 } else { 1212 }
	}
	cohorts := log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC COHORT:'))
	assert cohorts.len == 4
	seen.clear()
	for row in cohorts {
		f := row.fields()
		assert f.len == 12 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
			'namespace=0',
			'namespace=1',
		]
		key := f[3] + f[4]
		assert key !in seen
		seen[key] = true
		assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1
		if f[4] == 'namespace=1' {
			assert f[5] == 'self=2'
		}
		assert f[6] == 'uid=' + if f[3] == 'ordinary=1' { '1000' } else { '0' }
		assert f[7] == 'page=' + if arch == 'aarch64' && !reference { '16384' } else { '4096' }
		assert f[8..11] == ['raw=468', 'classes=6', 'layouts=3']
		assert f[11].starts_with('ipc=') && f[11].all_after('=').u64()>0
	}
	for label in ['CHILDREN:', 'CHILDRENFINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC ' + label))
		assert rows.len == 4
		seen.clear()
		for row in rows {
			f := row.fields()
			assert f.len == 7 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
				'namespace=0',
				'namespace=1',
			]
			key := f[3] + f[4]
			assert key !in seen
			seen[key] = true
			assert f[5] == 'valid=36' && f[6] == 'unexpected='+if phase=='before' {'36'} else {'0'}
		}
	}

	if phase == 'before' {
		original_errors(log)
		assert log.contains('LINUX CLONEIPC DETAIL:') && log.contains('LINUX CLONEIPC FAIL:') && !log.contains('LINUX CLONEIPC: PASS')
	} else {
		assert !log.contains('LINUX CLONEIPC DETAIL:') && !log.contains('LINUX CLONEIPC FAIL:')
	}
	if reference {
		assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX CLONEIPC REFERENCE: PASS') && !log.contains('LINUX CLONEIPC STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX CLONEIPC: PASS') == 1
	}
	assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn scope(area string, root string) ! {
 base:=os.read_file(area+'base.txt')!.trim_space()
 assert base=='1e90921fd6fd0394e0ba15c6a84bccf1b34f804a'
 helper:='// A new IPC namespace cannot share the old namespace\'s semaphore undo list.\n// Namespace permission precedes the conflict. NEWUSER needs separate credential\n// admission because it changes the capability domain before this check.\nfn clone_ipc_failure(flags u64) u64 {\n\tpair := proc.clone_newipc | u64(0x00040000)\n\tif flags & pair != pair || flags & proc.clone_newuser != 0 { return 0 }\n\tif !proc.current_has_capability(proc.cap_sys_admin) { return errno.eperm }\n\treturn errno.einval\n}\n\n'
 for path in ['linux_task.v','clone_arm64.v','clone_amd64.v'] {
  before:=os.read_file(area+'before-'+path)!;after:=os.read_file(area+'after-'+path)!
  mut expected:=before
  if path=='linux_task.v' {
   at:='// FS, descriptor and handler ownership is currently process-scoped.'
   assert before.count(at)==1;expected=before.replace(at,helper+at)
  } else {
   at:='\tmut cgroup := voidptr(unsafe { nil })'
   guard:='\tipc_failure := clone_ipc_failure(args.flags)\n\tif ipc_failure != 0 {\n\t\treturn errno.err, ipc_failure\n\t}\n\n'
   at_common:='\tif !supported_clone_sharing(flags) { return errno.err, errno.enotsup }'
   guard_common:='\tipc_failure := clone_ipc_failure(flags)\n\tif ipc_failure != 0 { return errno.err, ipc_failure }\n'
   assert before.count(at)==1 && before.count(at_common)==1
   expected=before.replace(at,guard+at).replace(at_common,guard_common+at_common)
  }
  assert expected==after && digest(root+'kernel/userland/'+path)==digest(area+'after-'+path)
  for suffix in ['arm','x86'] {
   tree:=area+'kernel-'+suffix
   assert git(tree,['show',base+':kernel/userland/'+path])!.trim_space()==before.trim_space()
   assert digest(tree+'/kernel/userland/'+path)==digest(area+'after-'+path)
  }
 }
 for suffix in ['arm','x86'] {
  tree:=area+'kernel-'+suffix
  assert git(tree,['rev-parse','HEAD'])! == base
  assert git(tree,['diff','--name-only','HEAD','--','kernel'])! == 'kernel/userland/clone_amd64.v\nkernel/userland/clone_arm64.v\nkernel/userland/linux_task.v'
  before:=os.read_file(area+'before-'+suffix+'.c')!;after:=os.read_file(area+'after-'+suffix+'.c')!
  mut expected:=before
  for api in ['clone3','common'] {
   marker:=if api=='clone3' {'\nmulti_return_u64_u64 userland__syscall_clone3(void* '+if suffix=='arm' {'_gpr_state'} else {'gpr_state'}+', u64 uargs, u64 size) {'} else if suffix=='arm' {'\nmulti_return_u64_u64 userland__do_clone_into(local__GPRState* state, u64 flags, u64 child_stack, u64 parent_tid, u64 tls, u64 child_tid, bool into_cgroup, void* cgroup) {'} else {'\nmulti_return_u64_u64 userland__do_clone(local__GPRState* state, u64 flags, u64 child_stack, u64 parent_tid, u64 child_tid, u64 tls, bool into_cgroup, void* cgroup) {'}
   old_body:=definition(before,marker);new_body:=definition(after,marker)
   at:=if api=='clone3' {'\tvoid* cgroup = (void*)(NULL);'} else {'\tif (!userland__supported_clone_sharing(flags)) {'}
   input:=if api=='clone3' {'args.flags'} else {'flags'}
   guard:='\tu64 ipc_failure = userland__clone_ipc_failure('+input+');\n\tif (ipc_failure != 0) {\n\t\treturn (multi_return_u64_u64){errno__err, ipc_failure};\n\t}\n'
   assert old_body.count(at)==1 && old_body.replace(at,guard+at)==new_body
   expected=expected.replace(old_body,new_body)
   for prohibited in ['memdup(', 'malloc(', 'calloc(', 'new_array', '__builtin_alloca('] {assert !new_body.contains(prohibited)}
  }
  new_helper:=definition(after,'\nu64 userland__clone_ipc_failure(u64 flags) {')
  assert new_helper=='\nu64 userland__clone_ipc_failure(u64 flags) {\n\tu64 pair = proc__clone_newipc | (u64)(0x00040000);\n\tif (((flags & pair) != pair) || ((flags & proc__clone_newuser) != 0)) {\n\t\treturn 0;\n\t}\n\tif (!proc__current_has_capability(proc__cap_sys_admin)) {\n\t\treturn errno__eperm;\n\t}\n\treturn errno__einval;\n}'
  prototype:='u64 userland__clone_ipc_failure(u64 flags);\n'
  assert after.count(prototype)==1 && after.count(new_helper)==1
  assert expected==after.replace(new_helper+'\n','').replace(prototype,''),'Exact whole C must differ only by IPC admission helper, prototype and four guards'
  for marker in ['\nbool proc__current_has_capability(i64 cap) {','\nbool proc__has_capability(proc__Process* process, i64 cap) {'] {
   callee:=definition(after,marker);assert callee==definition(before,marker)
   for prohibited in ['memdup(', 'malloc(', 'calloc(', 'new_array', '__builtin_alloca(', 'free(', 'spinlock', 'unpin', 'pin_process'] {assert !callee.contains(prohibited)}
  }
 }
}


fn repair_identity_probe(source string) string {
 mut result:=source
 changes:={
  '#include <sys/mman.h>':'#include <sys/mman.h>\n#include <sys/msg.h>'
  'wrongfd i32 ipc u64}':'wrongfd i32 ipc u64 queue i32}'
  'uid u32 ipc u64}':'uid u32 queue_visible i32}'
  'fn C.readlink(&char,&char,usize) isize':'fn C.readlink(&char,&char,usize) isize\nfn C.msgget(i32,i32) i32\nfn C.msgctl(i32,i32,voidptr) i32'
  'fn ipc_identity() u64':'fn queue_visible(queue i32) bool {unsafe {\n data:=C.alloca(512); C.memset(data,0,512)\n mut code:=C.__errno_location(); *code=0\n result:=C.msgctl(queue,C.IPC_STAT,data)\n if result==0 {return true}\n if result == -1 && *code==C.EINVAL {return false}\n fatal(31);return false\n}}\n\nfn ipc_identity() u64'
  'uid:C.getuid(),ipc:ipc_identity()}':'uid:C.getuid(),queue_visible:i32(queue_visible(state.queue))}'
  '&& if args.flags & u64(0x8000000) != 0 {reply.ipc != state.ipc} else {reply.ipc == state.ipc}':'&& reply.queue_visible == if args.flags & u64(0x8000000) != 0 {0} else {1}'
  'guarded:guarded&&no_children&&ipc_identity()==state.ipc':'guarded:guarded&&no_children&&queue_visible(state.queue)'
  '  state := &State(C.alloca':'  queue:=C.msgget(C.IPC_PRIVATE,C.IPC_CREAT|0o600)\n  if queue < 0 || !queue_visible(queue) {fatal(32)}\n  C.printf(c\'LINUX CLONEIPC QUEUE: ordinary=%d namespace=%d id=%d mode=0600\\n\',i32(ordinary),i32(namespace),queue)\n  state := &State(C.alloca'
  'wrongfd:wrongfd,ipc:ipc_identity()}':'wrongfd:wrongfd,ipc:ipc_identity(),queue:queue}'
  '  if !reference && !storage(state,ordinary,namespace) {good = false}':'  if ipc_identity()!=state.ipc || !queue_visible(queue) {fatal(33)}\n  if !reference && !storage(state,ordinary,namespace) {good = false}\n  if ipc_identity()!=state.ipc || !queue_visible(queue) {fatal(34)}\n  if C.msgctl(queue,C.IPC_RMID,nil)!=0 || queue_visible(queue) {fatal(35)}\n  C.printf(c\'LINUX CLONEIPC QUEUEREMOVED: ordinary=%d namespace=%d id=%d removed=1 ipc_unchanged=1\\n\',i32(ordinary),i32(namespace),queue)'
 }
 for before,after in changes {assert result.count(before)==1,before;result=result.replace(before,after)}
 return result
}

fn initial_semantics(log string, phase string, reference bool) {
 capabilities(log);descriptors(log)
 assert !log.contains('setup stage=') && !log.contains('LINUX CLONEIPC QUEUE:')
 for label in ['CASES:','FINAL:'] {
  rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC '+label));assert rows.len==24
  mut seen:=map[string]bool{}
  for row in rows {
   f:=row.fields();assert f.len==8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
   kind:=f[5].all_after('=').int();assert f[5].starts_with('kind=') && kind>=0 && kind<6
   key:=f[3]+f[4]+f[5];assert key !in seen;seen[key]=true
   bad:=if phase=='after' {0} else if kind in [0,1] {96} else if kind==2 {96} else if kind==4 {15} else {0}
   assert f[6]=='calls='+[96,96,108,60,72,36]![kind].str() && f[7]=='failures='+bad.str()
  }
 }
 for label in ['CHILDREN:','CHILDRENFINAL:'] {
  rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC '+label));assert rows.len==4
  mut seen:=map[string]bool{}
  for row in rows {
   f:=row.fields();assert f.len==7 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
   key:=f[3]+f[4];assert key !in seen;seen[key]=true
   assert f[5]=='valid=36' && f[6]=='unexpected='+if phase=='before' {'36'} else {'0'}
  }
 }
 if phase=='before' {original_errors(log)} else {assert !log.contains('LINUX CLONEIPC DETAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX CLONEIPC REFERENCE: PASS') && !log.contains('LINUX CLONEIPC FAIL:')}
 else {assert log.contains('LINUX CLONEIPC FAIL:') && !log.contains('LINUX CLONEIPC: PASS')}
}

fn initial_storage_refusal(log string, arch string) {
 mut counts:=[4]int{};mut growth:=[4]int{};mut seen:=map[string]bool{}
 for row in log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC SLAB:')) {
  f:=row.fields();assert f.len==8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[7]=='cycles=200'
  cohort:=f[3].all_after('=').int()+2*f[4].all_after('=').int()
  key:=f[3]+f[4]+f[5];assert key !in seen;seen[key]=true
  pair:=f[6].all_after('=').split('/');assert pair.len==2
  counts[cohort]++
  if f[5] in ['size=16','size=32','size=256','size=384','size=512'] {assert pair[1].i64()-pair[0].i64()>1000;growth[cohort]++}
 }
 for cohort in 0..4 {assert counts[cohort]==if arch=='aarch64' {18} else {14};assert growth[cohort]==5}
 rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEIPC STORAGE:'));assert rows.len==4
 seen.clear()
 for row in rows {
  f:=row.fields();assert f.len==8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5]=='cycles=200' && f[7]=='FAIL'
  key:=f[3]+f[4];assert key !in seen;seen[key]=true
  pair:=f[6].all_after('=').split('/');assert pair.len==2 && pair[0]==pair[1] && pair[0].u64()>0
 }
}

fn initial_refusal(area string, root string, out string) ! {
 old:=area+'identity-retention-refusal/'
 assert repair_identity_probe(os.read_file(old+'core.v')!)==os.read_file(root+'tests/linux-compat/cloneipcfixture/core.v')!
 assert os.read_file(old+'watch-refusal.log.status')!.trim_space()=='1' && os.read_file(old+'watch-refusal.log')!.contains('code.int() == if phase')
 profiles:=object(old+'native-profile-inputs.json')!;assert profiles.len==84
 for path,expected in profiles {assert digest(old+'states/'+path)==expected.str()}
 for arch,suffix in {'aarch64':'arm','x86_64':'x86'} {
  for phase in ['before','after'] {
   state:=old+'states/'+phase+'-'+suffix
   value:=object(state+'/receipt.json')!
   assert value['architecture']!.str()==arch && value['kernel_sha256']!.str()==digest(state+'/kernel/bin/vinix')
   kernel_folder:=if phase=='before' {'baseline-'+suffix} else {'kernel-'+suffix}
   assert value['kernel_sha256']!.str()==digest(area+kernel_folder+'/kernel/bin/vinix')
   names:=if phase=='before' {['cloneipc']} else {['cloneipc','runtime','clonepidguard']}
   rows:=value['results']!.as_array();assert rows.len==names.len
   for index,row in rows {
    entry:=row.as_map();name:=entry['name']!.str();assert name==names[index]
    expected_code:=if index==0 {1} else {0}
    assert entry['exit_code']!.int()==expected_code && entry['detail']!.str()==''
    probe:=state+'/'+name
    for label,path in {'source_sha256':state+'/sources/'+name+'fixture/core.v','init_sha256':probe+'/init','iso_sha256':probe+'/test.iso'} {assert entry[label]!.str()==digest(path)}
    if index==0 {
     assert entry['source_sha256']!.str()==digest(old+'core.v')
     c:=os.read_file(probe+'/fixture.c')!;assert c.count('alloca(')==11
     for forbidden in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'new_array', 'v_fixed_index'] {assert !c.contains(forbidden)}
     assert digest(probe+'/fixture.c')==digest(old+'states/before-'+suffix+'/cloneipc/fixture.c') && digest(probe+'/init')==digest(old+'states/before-'+suffix+'/cloneipc/init')
     log:=os.read_file(probe+'/serial.log')!;initial_semantics(log,phase,false);initial_storage_refusal(log,arch)
    } else {
     assert entry['source_sha256']!.str()==digest(root+'tests/linux-compat/'+name+'fixture/core.v')
     assert os.read_file(probe+'/serial.log')!.contains('LINUX '+name.to_upper()+': PASS')
     assert !os.read_file(probe+'/serial.log')!.contains('Kernel panic')
    }
    publish(probe+'/serial.log',out+'cloneipc-identity-retention-'+phase+'-'+suffix+'-'+name+'.log')!
   }
   assert os.read_file(state+'.log.status')!.trim_space()=='1'
   publish(state+'/receipt.json',out+'cloneipc-identity-retention-'+phase+'-'+suffix+'-receipt.json')!
   publish(state+'.log',out+'cloneipc-identity-retention-'+phase+'-'+suffix+'-producer.log')!
  }
  state:=old+'states/reference-'+suffix
  value:=object(state+'/receipt.json')!;assert value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int()==0
  artifacts:=value['artifacts']!.as_map_of_strings()
  for label,path in {'kernel':'linux','probe':'probe','wrapper_source':'source/cloneipcreferenceinit/core.v','wrapper_c':'fixture.c','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log','serial_adapter_c':'serial.c'} {assert artifacts[label]==digest(state+'/'+path)}
  assert artifacts['probe']==digest(old+'states/before-'+suffix+'/cloneipc/init')
  initial_semantics(os.read_file(state+'/serial.log')!,'after',true)
  publish(state+'/receipt.json',out+'cloneipc-identity-retention-reference-'+suffix+'-receipt.json')!
  publish(state+'/serial.log',out+'cloneipc-identity-retention-reference-'+suffix+'.log')!
 }
 mut pins:=map[string]string{}
 for path in os.walk_ext(old,'') {if os.inode(path).typ==.regular {pins[path]=digest(path)}}
 for name in ['archive-identity.v','archive-identity','canary-repair.txt','repair-host.v','save-host-attempt.v'] {pins[area+name]=digest(area+name)}
 os.write_file(area+'identity-retention-inputs.json',json2.encode(pins,prettify:true)+'\n')!
 publish(area+'identity-retention-inputs.json',out+'cloneipc-identity-retention-inputs.json')!
 publish(old+'watch-refusal.log',out+'cloneipc-identity-retention-watch-refusal.log')!
}


fn main() {
	if '--scope-only' in os.args {
		scope(os.args[2].trim_right('/') + '/', '/Users/alex/code/vinix/')!
		println('Native cloneipc exact source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'cloneipc assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len in [2, 3] && (os.args.len == 2 || os.args[2] == '--verify-only'), 'Usage: cloneipc-check.v EVIDENCE-AREA [--verify-only] (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	root := '/Users/alex/code/vinix/'
	out := if os.args.len == 3 {
		area + 'preview/'
	} else {
		root + 'tests/linux-compat/results/2026-10-16/'
	}
	os.mkdir_all(out)!
	scope(area, root)!
	initial_refusal(area, root, out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'cloneipc assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		area + 'states/reference-arm/serial.log', 'aarch64'], 'cloneipc baseline failure markers required'))!
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		before := area + 'states/before-' + suffix
		after := area + 'states/after-' + suffix
		mut artifacts := map[string]string{}
		for phase, state in {
			'before': before
			'after':  after
		} {
			names := if phase == 'before' {
				['cloneipc']
			} else {
				['cloneipc']
			}
			kernel := digest(state + '/kernel/bin/vinix')
			assert kernel == digest(area + '/' + if phase == 'before' {
				'baseline-' + suffix
			} else {
				'kernel-' + suffix
			} + '/kernel/bin/vinix')
			got := receipt(state, arch, kernel, names, phase == 'before')!
			for key, hash in got { artifacts[phase + '_' + key] = hash }
			log := os.read_file(state + '/cloneipc/serial.log')!
			if phase == 'before' {
				failure(log, arch)
			} else {
				semantics(log, 'after', arch, false)
			}
			storage(log, arch, phase)
			probe_c := os.read_file(state + '/cloneipc/fixture.c')!
			for forbidden in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index'] {
				assert !probe_c.contains(forbidden), forbidden
			}
			assert probe_c.count('alloca(') == 12
			assert digest(state + '/cloneipc/fixture.c') == digest(before + '/cloneipc/fixture.c') && digest(state + '/cloneipc/init') == digest(before + '/cloneipc/init')
			for name in names {
				publish(state + '/' + name + '/serial.log', out + 'cloneipc-' + phase + '-' + suffix + '-' + name + '.log')!
			}
			for path in ['receipt.json'] {
				publish(state + '/' + path, out + 'cloneipc-' + phase + '-' + suffix + '-' + path)!
			}
			publish(state + '.log', out + 'cloneipc-' + phase + '-' + suffix + '-producer.log')!
			publish(area + 'build-' + phase + '-' + suffix + '.log', out + 'cloneipc-build-' + phase + '-' + suffix + '.log')!
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build_log'] = digest(area + 'build-' + phase + '-' + suffix + '.log')
		}
		refstate := area + 'states/reference-' + suffix
		reference := reference_receipt(refstate, arch, digest(before + '/cloneipc/init'))!
		for key, hash in reference { artifacts['reference_' + key] = hash }
		publish(refstate + '/receipt.json', out + 'cloneipc-reference-' + suffix + '-receipt.json')!
		publish(refstate + '/serial.log', out + 'cloneipc-reference-' + suffix + '.log')!
		mut sources := {
			'auditor':              digest(@FILE)
			'controller':           digest(root + 'tests/linux-compat/run.v')
			'reference_controller': digest(root + 'tests/linux-compat/cloneipc-reference.v')
			'probe':                digest(root + 'tests/linux-compat/cloneipcfixture/core.v')
		}
		for path in ['linux_task.v', 'clone_arm64.v', 'clone_amd64.v'] {
			sources['kernel/userland/' + path] = digest(root + 'kernel/userland/' + path)
		}
		value := Evidence{ architecture: arch, context: '1872 native musl clone/clone3 NEWIPC SYSVSEM conflict controls; Linux identical ELF; original 1212 EBADF/ENOTSUP/unwanted-child failures versus capability-first EPERM/EINVAL; root/UID1000 effective SYS_ADMIN off/on; queue-visibility canaries and cohort IPC identities, earlier ABI errors, bit-absent cgroup admission and real fork/reap; identical refusal-input retention with proc identity reads outside the window; initial proc-identity-loop strict failures retained; repeated IPC namespace construction and full SEM_UNDO semantics unqualified', base_commit: os.read_file(area + 'base.txt')!.trim_space(), artifacts: artifacts, source_inputs: sources }
		os.write_file(area + 'evidence-' + arch + '.json', json2.encode(value, prettify: true) + '\n')!
		publish(area + 'evidence-' + arch + '.json', out + 'cloneipc-evidence-' + arch + '.json')!
	}
	assert digest(area + 'states/preflight-arm/fixture.c') == digest(area + 'states/before-arm/cloneipc/fixture.c')
	assert os.read_file(area + 'preflight.log')!.contains('Probe compiler preflight: PASS')
	pins := object('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler-inputs.json')!
	assert pins.len == 15146
	for path, hash in pins {
		assert digest('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/' + path) == hash.str(), path
	}
	sdk := object('/Users/alex/.cache/vinix-linux-compat/tidfault-20261015/sdk-inputs.json')!
	assert sdk.len == 2014
	for path, hash in sdk {
		assert digest(area + 'sdk/' + path) == hash.str(), path
	}
	for suffix in ['arm', 'x86'] {
		view := area + 'kernel-' + suffix + '/'
		inventory := object(view + 'docs/linux-syscall-coverage.json')!
		inputs := inventory['inputs']!.as_map()
		assert inputs.len == 67
		for path, hash in inputs {
			assert digest(view + path) == hash.str(), path
		}
		assert digest(view + 'docs/linux-syscall-coverage.json') == digest(area + 'kernel-arm/docs/linux-syscall-coverage.json')
	}
	retained := object(area + 'watch-final-retained-inputs.json')!
	assert retained.len == 42
	for path, hash in retained {
		assert path.starts_with(area + 'states/') && os.inode(path).typ == .regular && digest(path) == hash.str()
		if path.ends_with('.compiler.json') {
			command := object(path)!
			assert command['status']!.str() == '0' && command['arguments']!.str().contains('--target=aarch64-linux-musl') && command['arguments']!.str().contains('--sysroot=' + area + 'sdk')
		}
	}
	mut walked := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['cloneipc']
			} else {
				['cloneipc']
			}
			for name in names {
				probe := area + 'states/' + phase + '-' + suffix + '/' + name
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
	assert walked.len == retained.len && os.read_file(area + 'watch-final.log')!.split_into_lines().len == 4
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	mut diagnostics := map[string]string{}
	for path in ['manage.v', 'manage', 'arm-cc.v', 'arm-cc', 'preflight.v', 'preflight', 'preflight.log',
		'states/preflight-arm/fixture.c', 'states/preflight-arm/init', 'assertion-control.log',
		'passing-log-control.log', 'before-linux_task.v', 'after-linux_task.v', 'before-clone_arm64.v',
		'after-clone_arm64.v', 'before-clone_amd64.v', 'after-clone_amd64.v', 'watch.v',
		'watch-final-retained-inputs.json', 'coverage-check.log', 'linux-fork-v6.12.c', 'linux-cgroup-v6.12.c','linux-nsproxy-v6.12.c'] {
		diagnostics[path] = digest(area + path)
	}
 for path in ['early-reference.v','early-reference','scope.log','scope.log.status'] {diagnostics[path] = digest(area+path)}
 publish(area+'scope.log',out+'cloneipc-scope.log')!
	os.write_file(area + 'diagnostic-pins.json', json2.encode(diagnostics, prettify: true) + '\n')!
	publish(area + 'diagnostic-pins.json', out + 'cloneipc-diagnostic-pins.json')!
	for path in ['assertion-control.log', 'passing-log-control.log', 'watch-final.log', 'preflight.log'] {
		publish(area + path, out + 'cloneipc-' + path)!
	}
	println('Native cloneipc conformance audit: PASS')
}
