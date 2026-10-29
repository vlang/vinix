// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the production account UI transport and input state machine with
// deterministic syscall outcomes. No Android VM or copied parser is involved.
// VINIX_ACCOUNT_UI_EVIDENCE may name a new absolute external bundle directory.
module main

import crypto.sha256
import json2
import os

struct UiArtifact {
	path   string
	sha256 string
}

struct UiReceipt {
	source_revision string
	compiler        string
	compiler_sha256 string
	compile_args    []string
	compile_exit    int
	run_args        []string
	run_exit        int
	artifacts       []UiArtifact
}

fn ui_function(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn ui_struct(source string, name string) !string {
	start := source.index('struct ' + name + ' {') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn ui_io(source string) string {
	mut result := source
	for name in ['close', 'read', 'recvmsg', 'fcntl', 'fstat', 'mmap', 'munmap', 'poll', 'pread',
		'pthread_mutex_lock', 'pthread_mutex_unlock', 'free'] {
		result = result.replace('C.' + name + '(', 'probe_' + name + '(')
	}
	return result.replace('C.stat{}', 'ProbeStat{}')
		.replace('C.__errno_location()', 'probe_errno()')
		.replace('C.iovec', 'UiVector').replace('C.msghdr', 'UiMessage')
		.replace('C.cmsghdr', 'UiAncillary')
}

fn main() {
	assert os.args.len in [1, 2], 'usage: check-account-ui [REPO]'
	repo := if os.args.len == 2 { os.real_path(os.args[1]) } else { os.getwd() }
	source := os.read_file(repo + '/build-support/android/nativews/account_ui.v')!
	runtime := os.read_file(repo + '/build-support/android/nativews/runtime.v')!
	service := os.read_file(repo + '/build-support/android/nativews/account_service.v')!
	mut program := ui_probe
	program += '\n' + ui_struct(service, 'WsAuthSlot')!.replace('next &WsAuthSlot\n', 'next &WsAuthSlot = unsafe { nil }\n')
	for name in ['ws_auth_slot_free', 'ws_auth_error_fields'] {
		program += '\n' + ui_io(ui_function(service, name)!)
	}
	for name in ['WsEvent', 'WsSurface', 'WsPoll'] { program += '\n' + ui_struct(runtime, name)! }
	for name in ['C.iovec', 'C.msghdr', 'C.cmsghdr'] {
		// C aggregate zero initialization permits null pointer fields. Preserve
		// that representation when modeling Linux C layouts as host V structs.
		program += '\n' + ui_io(ui_struct(source, name)!)
			.replace('&UiVector\n', '&UiVector = unsafe { nil }\n')
	}
	for name in ['ws_ui_be32', 'ws_ui_close_pair', 'ws_ui_rights', 'ws_ui_receive', 'ws_ui_descriptors',
		'ws_ui_dispatch', 'ws_service_ui_input', 'ws_ui_clear_exception', 'ws_ui_cancel',
		'ws_service_ui_shutdown'] {
		program += '\n' + ui_io(ui_function(source, name)!)
	}
	program += ui_cases
	program += '\nfn main() {\n assert rights_suite(ws_ui_rights, true)\n assert receive_suite(ws_ui_receive, true)\n assert descriptor_suite(ws_ui_descriptors, true)\n assert input_suite(ws_service_ui_input, true)\n assert cancel_suite(ws_ui_cancel, true)\n assert shutdown_suite(ws_service_ui_shutdown, true)\n'
	for name in ['ws_ui_rights', 'ws_ui_receive', 'ws_ui_descriptors', 'ws_service_ui_input'] {
		original := ui_io(ui_function(source, name)!)
		for i, mutation in ui_mutations(name, original) {
			assert mutation != original, 'mutation no longer applies: ${name}:${i}'
			mutant := name + '_mutant_' + i.str()
			program = program.replace('\nfn main() {', '\n' + mutation.replace('fn ' + name + '(', 'fn ' + mutant + '(') + '\nfn main() {')
			suite := match name {
				'ws_ui_rights' { 'rights_suite' }
				'ws_ui_receive' { 'receive_suite' }
				'ws_ui_descriptors' { 'descriptor_suite' }
				else { 'input_suite' }
			}
			program += ' assert !${suite}(${mutant}, false), "escaped ${mutant}"\n'
		}
	}
	dispatch := ui_io(ui_function(source, 'ws_ui_dispatch')!)
	for i, mutation in [dispatch.replace('pop_frame(e)', ''),
		dispatch.replace(')(e, 128) < 0', ')(e, 128) < -1')] {
		assert mutation != dispatch, 'dispatch mutation no longer applies: ${i}'
		mutant := 'ws_ui_dispatch_mutant_' + i.str()
		input_name := 'input_dispatch_mutant_' + i.str()
		copy := ui_io(ui_function(source, 'ws_service_ui_input')!)
			.replace('fn ws_service_ui_input(', 'fn ' + input_name + '(')
			.replace('ws_ui_dispatch(e)', mutant + '(e)')
		program = program.replace('\nfn main() {', '\n' + mutation.replace('fn ws_ui_dispatch(', 'fn ' + mutant + '(') + '\n' + copy + '\nfn main() {')
		program += ' assert !input_suite(${input_name}, false), "escaped ${mutant}"\n'
	}
	for name in ['ws_ui_cancel', 'ws_service_ui_shutdown'] {
		original := ui_io(ui_function(source, name)!)
		for i, mutation in ui_mutations(name, original) {
			assert mutation != original, 'mutation no longer applies: ${name}:${i}'
			mutant := name + '_mutant_' + i.str()
			program = program.replace('\nfn main() {', '\n' + mutation.replace('fn ' + name + '(', 'fn ' + mutant + '(') + '\nfn main() {')
			suite := if name == 'ws_ui_cancel' { 'cancel_suite' } else { 'shutdown_suite' }
			program += ' assert !${suite}(${mutant}, false), "escaped ${mutant}"\n'
		}
	}
	program += ' println("ACCOUNT-UI-PASS rights receive descriptors partial-input eof-service cancel teardown mutations")\n}\n'
	output := ui_execute(program, repo, {
		'account_ui.v':       source
		'runtime.v':          runtime
		'account_service.v':  service
		'check-account-ui.v': os.read_file(repo + '/tests/native-android-ws/check-account-ui.v')!
	})!
	assert output == 'ACCOUNT-UI-PASS rights receive descriptors partial-input eof-service cancel teardown mutations'
	println(output)
}

fn ui_execute(program string, repo string, sources map[string]string) !string {
	work := os.join_path(os.temp_dir(), 'vinix-account-ui-' + os.getpid().str())
	assert !os.exists(work)
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	os.write_file(work + '/main.v', program)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	args := [compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', '-o', work + '/probe',
		work + '/main.v']
	compiled := os.exec(args)
	run_args := [work + '/probe']
	ran := if compiled.exit_code == 0 { os.exec(run_args) } else { os.Result{ exit_code: -1 } }
	evidence := os.getenv('VINIX_ACCOUNT_UI_EVIDENCE')
	if evidence != '' {
		assert os.is_abs_path(evidence) && !os.exists(evidence), 'evidence must be a new absolute directory'
		os.mkdir_all(evidence)!
		mut artifacts := []UiArtifact{}
		mut captured := sources.clone()
		captured['extracted-probe.v'] = program
		captured['compile.log'] = compiled.output
		captured['run.log'] = ran.output
		mut names := captured.keys()
		names.sort()
		for name in names {
			contents := captured[name]
			os.write_file(evidence + '/' + name, contents)!
			artifacts << UiArtifact{ path: name, sha256: sha256.sum(contents.bytes()).hex() }
		}
		revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
		assert revision.exit_code == 0
		compiler_path := os.real_path(os.find_abs_path_of_executable(compiler)!)
		os.write_file(evidence + '/receipt.json', json2.encode(UiReceipt{
			source_revision: revision.output.trim_space()
			compiler:        compiler_path
			compiler_sha256: sha256.sum(os.read_bytes(compiler_path)!).hex()
			compile_args:    args
			compile_exit:    compiled.exit_code
			run_args:        run_args
			run_exit:        ran.exit_code
			artifacts:       artifacts
		},
			prettify:       true
			legacy_layout:  true
			escape_unicode: true
			time_as_unix:   true
		))!
	}
	if compiled.exit_code != 0 { return error(compiled.output) }
	if ran.exit_code != 0 { return error(ran.output) }
	return ran.output.trim_space()
}

const ui_probe = '
module main
#include <errno.h>
#include <string.h>
#include <alloca.h>
fn C.alloca(usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
struct UiState {
mut:
 input i32 = 42
 running bool = true
 service bool = true
 activity voidptr = voidptr(2)
 surface &WsSurface = unsafe { nil }
 width i32 = 64
 height i32 = 64
 back_count i32
 back_stack [64]voidptr
 focused voidptr
 pressed voidptr
 dialog voidptr
 dirty bool
}
type Rights = fn (&u8, usize, i32, &i32, &u32) bool
type Receive = fn (&u8, &i32) bool
type Descriptors = fn (&u8, i32, i32) bool
type Input = fn (voidptr) bool
type FramePush = fn (voidptr, i32) i32
type WsApplicationException = fn (voidptr) voidptr
type WsApplicationClear = fn (voidptr)
type WsApplicationThrow = fn (voidptr, voidptr) i32
type Drop = fn (voidptr, voidptr)
type Cancel = fn (voidptr)
struct ReceiveStep {
 bytes []u8
 control []u8
 flags i32
 result i64
 code i32
}
struct ProbeStat {
mut:
 st_size i64
 st_mode u32
}
struct ReadStep {
 bytes []u8
 result i64
 code i32
}
struct Probe {
mut:
 closed []i32
 reads []ReadStep
 read_index int
 read_offset int
 code i32
 keys [][]u8
 pointer []WsEvent
 exception bool
 receive []ReceiveStep
 receive_index int
 now i64
 poll_result i32 = 1
 poll_code i32
 poll_calls int
 surface_flags i32 = 2
 input_flags i32
 seals i32 = 6
 fcntl_error i32 = -1
 fcntl_calls []i32
 stat_error i32 = -1
 surface_info ProbeStat = ProbeStat{st_size:32816,st_mode:0x8000}
 input_info ProbeStat = ProbeStat{st_mode:0x1000}
 header WsSurface = WsSurface{magic:0x31534656,version:1,header_size:48,width:64,height:64,stride:256,format:1,reader:0xffffffff,buffer_size:16384}
 pread_result i64 = 48
 map_error bool
 mappings int
 frame_depth int
 pushes int
 pops int
 unsafe_jni int
 fail_push bool
 dispatch_exception bool
 lock_depth int
 lock_errors int
 builders []u64
 builder_freed int
 sent int
 field_calls int
 slot_freed []u64
 fail_builder bool
 fail_fields bool
 lifecycle []string
 drops []voidptr
 detached []voidptr
 unmaps int
 clear_count int
 throws int
 complete_during_destroy bool
 results int
 lifecycle_exception bool
 cancel_exception bool
 secondary_exception bool
 reentrant_shutdown bool
 reentered bool
 background_count int
}
__global p = Probe{}
__global ws = &UiState{}
__global ws_ui_channel i32
__global ws_ui_mapping_size usize
__global ws_ui_event WsEvent
__global ws_ui_header_used u32
__global ws_ui_text [4096]u8
__global ws_ui_text_used u32
__global ws_ui_live bool
__global ws_ui_closing bool
__global ws_ui_retained bool
__global ws_ui_session u64
__global ws_auth_ready bool
__global ws_auth_handle voidptr
__global ws_auth_slots &WsAuthSlot
__global ws_auth_mutex i32
fn probe_errno() &i32 { return unsafe { &p.code } }
fn probe_close(fd i32) i32 { p.closed << fd; return 0 }
fn ws_millis() i64 { return p.now }
fn probe_poll(ready &WsPoll, count usize, timeout i32) i32 {
 assert count == 1 && ready.fd == 33 && timeout > 0 && timeout <= 1000
 p.poll_calls++
 p.code = p.poll_code
 p.now++
 return p.poll_result
}
fn probe_recvmsg(fd i32, message &UiMessage, flags i32) isize {
 assert fd == 33 && flags == 0x40000040 && message.msg_iovlen == 1
 if p.receive_index >= p.receive.len { p.code = C.EAGAIN; return -1 }
 entry := p.receive[p.receive_index]
 p.receive_index++
 p.code = entry.code
 unsafe {
  assert usize(entry.bytes.len) <= message.msg_iov.iov_len && entry.control.len <= 4096
  if entry.bytes.len != 0 { C.memcpy(message.msg_iov.iov_base, entry.bytes.data, usize(entry.bytes.len)) }
  if entry.control.len != 0 { C.memcpy(message.msg_control, entry.control.data, usize(entry.control.len)) }
  message.msg_controllen = usize(entry.control.len)
  message.msg_flags = entry.flags
 }
 return isize(entry.result)
}
fn probe_fcntl(fd i32, command i32, args ...i32) i32 {
 assert fd in [18,42]
 p.fcntl_calls << command
 if command == p.fcntl_error { return -1 }
 if command == 3 { return if fd == 18 { p.surface_flags } else { p.input_flags } }
 if command == 1034 { assert fd == 18; return p.seals }
 if command == 1 { return 16 }
 assert fd == 42 && args.len == 1
 if command == 2 { assert args[0] == 17; return 0 }
 assert command == 4 && args[0] == p.input_flags | 0x800
 return 0
}
fn probe_fstat(fd i32, info &ProbeStat) i32 {
 assert fd in [18,42]
 if p.stat_error == fd { return -1 }
 unsafe { *info = if fd == 18 { p.surface_info } else { p.input_info } }
 return 0
}
fn probe_pread(fd i32, output voidptr, length usize, offset i64) isize {
 assert fd == 18 && length == 48 && offset == 0
 if p.pread_result == 48 { unsafe { C.memcpy(output, &p.header, 48) } }
 return isize(p.pread_result)
}
fn probe_mmap(address voidptr, length usize, protection i32, flags i32, fd i32, offset i64) voidptr {
 assert address == unsafe { nil } && length == 32816 && protection == 3 && flags == 1 && fd == 18 && offset == 0
 p.mappings++
 if p.map_error { return voidptr(-1) }
 return unsafe { voidptr(&p.header) }
}
fn reset() {
 p = Probe{}
 ws = &UiState{}
 ws_ui_channel = 33
 ws_ui_mapping_size = 0
 ws_ui_event = WsEvent{}
 ws_ui_header_used = 0
 ws_ui_text_used = 0
 ws_ui_text = [4096]u8{}
 ws_ui_live = true
 ws_ui_closing = false
 ws_ui_retained = false
 ws_ui_session = 0
 ws_auth_ready = true
 ws_auth_handle = voidptr(17)
 ws_auth_slots = unsafe { nil }
 ws_auth_mutex = 0
}
fn probe_read(fd i32, output voidptr, length usize) isize {
 assert fd == 42 && length > 0
 if p.read_index == p.reads.len { p.code = C.EAGAIN; return -1 }
 step := p.reads[p.read_index]
 if step.result <= 0 {
  p.read_index++
  p.read_offset = 0
  p.code = step.code
  return isize(step.result)
 }
 available := step.bytes.len - p.read_offset
 count := if int(length) < available { int(length) } else { available }
 assert count > 0 && step.result == step.bytes.len
 unsafe { C.memcpy(output, &u8(step.bytes.data) + p.read_offset, usize(count)) }
 p.read_offset += count
 if p.read_offset == step.bytes.len { p.read_offset = 0; p.read_index++ }
 return isize(count)
}
fn pending(e voidptr) bool { assert e == voidptr(1); return p.exception }
fn slot(e voidptr, index i32) voidptr {
 assert e == voidptr(1)
 return match index {
  13 { voidptr(probe_throw) }
  15 { voidptr(probe_exception) }
  17 { voidptr(probe_clear) }
  19 { voidptr(probe_push) }
  22,23 { voidptr(probe_drop) }
  else { panic("unexpected JNI slot") }
 }
}
fn probe_push(e voidptr, capacity i32) i32 {
 assert e == voidptr(1) && capacity == 128
 if p.fail_push { return -1 }
 p.pushes++; p.frame_depth++
 return 0
}
fn pop_frame(e voidptr) {
 assert e == voidptr(1)
 if p.frame_depth != 1 { p.unsafe_jni++ }
 p.pops++; p.frame_depth--
}
fn ws_keys(e voidptr, bytes &u8, length u32) {
 assert e == voidptr(1) && length <= 4096
 if p.frame_depth != 1 { p.unsafe_jni++ }
 p.keys << unsafe { bytes.vbytes(int(length)).clone() }
 if p.dispatch_exception { p.exception = true }
}
fn ws_pointer(e voidptr, event &WsEvent) {
 assert e == voidptr(1)
 if p.frame_depth != 1 { p.unsafe_jni++ }
 p.pointer << *event
 if p.dispatch_exception { p.exception = true }
}
fn event_bytes(kind u32, length u32) []u8 {
 event := WsEvent{magic: 0x31494e56,kind:kind,x:5,y:6,value:7,length:length}
 return unsafe { (&u8(&event)).vbytes(int(sizeof(WsEvent))).clone() }
}
fn step(bytes []u8) ReadStep { return ReadStep{bytes:bytes,result:i64(bytes.len)} }
fn again() ReadStep { return ReadStep{result:-1,code:C.EAGAIN} }
fn interrupted() ReadStep { return ReadStep{result:-1,code:C.EINTR} }
fn eof() ReadStep { return ReadStep{result:0} }
fn probe_pthread_mutex_lock(mutex &i32) i32 {
 if p.lock_depth != 0 { p.lock_errors++ }
 p.lock_depth++
 return 0
}
fn probe_pthread_mutex_unlock(mutex &i32) i32 {
 if p.lock_depth != 1 { p.lock_errors++ }
 p.lock_depth--
 return 0
}
fn ws_auth_response(handle voidptr,id u64,kind u16) voidptr {
 assert handle == voidptr(17) && kind == 2
 if p.lock_depth != 1 { p.lock_errors++ }
 p.builders << id
 if p.fail_builder { return unsafe { nil } }
 return voidptr(18)
}
fn ws_auth_option(builder voidptr,key &char,tag u16,text &char,number i64) i32 {
 assert builder == voidptr(18)
 if p.lock_depth != 0 { p.lock_errors++ }
 p.field_calls++
 if unsafe { cstring_to_vstring(key) } == "errorCode" {
  assert tag == 3 && text == unsafe { nil } && number == 4
 } else {
  assert unsafe { cstring_to_vstring(key) } == "errorMessage" && tag == 1 && number == 0
  assert unsafe { cstring_to_vstring(text) } == "account UI closed"
 }
 return if p.fail_fields { -1 } else { 0 }
}
fn ws_auth_send(builder voidptr) i32 {
 assert builder == voidptr(18)
 if p.lock_depth != 0 { p.lock_errors++ }
 p.sent++
 return 0
}
fn ws_auth_free(builder voidptr) {
 assert builder == voidptr(18)
 if p.lock_depth != 0 { p.lock_errors++ }
 p.builder_freed++
}
fn probe_free(node voidptr) {
 if p.lock_depth != 0 { p.lock_errors++ }
 p.slot_freed << unsafe { (&WsAuthSlot(node)).id }
 // Fault-inject a late cleanup boundary that leaves JNI pending.
 if p.cancel_exception { p.exception = true; p.secondary_exception = true }
}
fn probe_exception(e voidptr) voidptr { assert e == voidptr(1) && p.exception && !p.secondary_exception; return voidptr(99) }
fn probe_clear(e voidptr) { assert e == voidptr(1); p.exception = false; p.secondary_exception = false; p.clear_count++ }
fn probe_throw(e voidptr,exception voidptr) i32 {
 assert e == voidptr(1) && exception == voidptr(99)
 // Model CheckJNI rejection in the safety result, allowing mutant cases to
 // fail the suite without terminating all the other behavioral checks.
 if p.exception { p.unsafe_jni++; return -1 }
 p.exception = true; p.throws++
 return 0
}
fn probe_drop(e voidptr,reference voidptr) {
 assert e == voidptr(1)
 if p.lock_depth != 0 { p.lock_errors++ }
 p.drops << reference
}
fn call(e voidptr,activity voidptr,class &char,method &char,signature &char,args voidptr) {
 assert e == voidptr(1) && activity != unsafe { nil }
 if p.exception || !ws_ui_closing || ws.activity != unsafe { nil } { p.unsafe_jni++ }
 name := unsafe { cstring_to_vstring(method) }
 p.lifecycle << name
 if name == "vinixPerformDestroy" && p.complete_during_destroy && ws_auth_slots != unsafe { nil } {
  node := ws_auth_slots
  unsafe { ws_auth_slots = node.next }
  p.results++
  ws_auth_slot_free(e,node)
 }
 if name == "vinixPerformDestroy" && p.reentrant_shutdown && !p.reentered {
  p.reentered = true
  ws_service_ui_shutdown(e)
 }
 if p.lifecycle_exception { p.exception = true }
}
fn activity_decor(e voidptr,activity voidptr) voidptr {
 assert e == voidptr(1) && activity != unsafe { nil }
 if p.exception { p.unsafe_jni++ }
 return voidptr(88)
}
fn ws_detach_view(e voidptr,decor voidptr) {
 assert e == voidptr(1) && decor == voidptr(88)
 if p.exception { p.unsafe_jni++ }
 p.detached << decor
}
fn ws_uid_lifecycle(e voidptr,state i32) {
 assert e == voidptr(1) && state == 300
 if p.exception || ws.activity != unsafe { nil } || ws.back_count != 0 { p.unsafe_jni++ }
 p.background_count++
 if p.lifecycle_exception { p.exception = true }
}
fn probe_munmap(address voidptr,length usize) i32 {
 assert address == unsafe { voidptr(&p.header) } && length == 32816
 p.unmaps++
 return 0
}
'

const ui_cases = '
fn check(ok bool, name string, loud bool) bool {
 valid := ok && p.frame_depth == 0 && p.pushes == p.pops && p.unsafe_jni == 0 && p.pushes == p.keys.len + p.pointer.len && p.lock_depth == 0 && p.lock_errors == 0
 if !valid && loud { eprintln("account UI case failed: " + name) }
 return valid
}
fn ancillary(fds []i32, declared int, tail int) []u8 {
 size := int(sizeof(UiAncillary)) + fds.len * 4
 mut bytes := []u8{len:size + tail}
 header := UiAncillary{cmsg_len:usize(if declared < 0 {size} else {declared}),cmsg_level:1,cmsg_type:1}
 unsafe {
  C.memcpy(bytes.data, &header, sizeof(UiAncillary))
  if fds.len > 0 { C.memcpy(&u8(bytes.data) + sizeof(UiAncillary), fds.data, usize(fds.len * 4)) }
 }
 return bytes
}
fn rights_case(run Rights, bytes []u8, flags i32, accepted bool, closed []i32, count u32, loud bool, name string) bool {
 reset()
 mut descriptors := [i32(-9),i32(-9)]!
 mut observed := u32(99)
 result := run(bytes.data, usize(bytes.len), flags, &descriptors[0], &observed)
 want := if accepted { [i32(18),i32(42)]! } else { [i32(-1),i32(-1)]! }
 return check(result == accepted && p.closed == closed && observed == count && descriptors == want, name,loud)
}
fn rights_suite(run Rights, loud bool) bool {
 if !rights_case(run,ancillary([i32(18),42],-1,0),0,true,[],2,loud,"two rights") { return false }
 for flags in [i32(8),32,40] {
  if !rights_case(run,ancillary([i32(18),42],-1,0),flags,false,[i32(18),42],2,loud,"truncated flags close rights") { return false }
 }
 if !rights_case(run,ancillary([i32(18)],-1,0),0,false,[i32(18)],1,loud,"one right") { return false }
 if !rights_case(run,ancillary([i32(18),42,43],-1,0),0,false,[i32(18),42,43],3,loud,"extra right cleanup") { return false }
 if !rights_case(run,ancillary([i32(18),18],-1,0),0,false,[i32(18)],1,loud,"duplicate right closed once") { return false }
 if !rights_case(run,ancillary([i32(18),1],-1,0),0,false,[i32(18),1],2,loud,"stdio right rejected and closed") { return false }
 if !rights_case(run,ancillary([i32(18),42],40,0),0,false,[i32(18),42],2,loud,"truncated ancillary length") { return false }
 if !rights_case(run,ancillary([i32(18),42],-1,1),0,false,[i32(18),42],2,loud,"trailing short header cleanup") { return false }
 mut multiple := ancillary([i32(18)],-1,4)
 multiple << ancillary([i32(42)],-1,0)
 if !rights_case(run,multiple,0,false,[i32(18),42],2,loud,"multiple rights messages") { return false }
 mut unknown := ancillary([i32(18),42],-1,0)
 unsafe { (&UiAncillary(unknown.data)).cmsg_type = 2 }
 if !rights_case(run,unknown,0,false,[],0,loud,"unknown ancillary") { return false }
 reset()
 mut out := [i32(8),9]!
 mut count := u32(99)
 if !check(!run(unsafe { nil },1,0,&out[0],&count) && out == [i32(-1),-1]! && count == 0,"null ancillary",loud) { return false }
 return true
}
fn received(bytes []u8, fds []i32) ReceiveStep {
 return ReceiveStep{bytes:bytes,control:if fds.len > 0 {ancillary(fds,-1,0)} else {[]u8{}},result:i64(bytes.len)}
}
fn receive_case(run Receive, entries []ReceiveStep, accepted bool, closed []i32, fds []i32, loud bool, name string) bool {
 reset()
 p.receive = entries
 mut frame := [64]u8{}
 mut output := [i32(-9),i32(-9)]!
 result := run(&frame[0],&output[0])
 want := if accepted { [fds[0],fds[1]]! } else { [i32(-1),-1]! }
 assembled := !accepted || frame[..] == []u8{len:64,init:u8(index)}
 return check(result == accepted && assembled && p.closed == closed && output == want && p.poll_calls <= 64,name,loud)
}
fn receive_suite(run Receive,loud bool) bool {
 bytes := []u8{len:64,init:u8(index)}
 if !receive_case(run,[received(bytes,[i32(18),42])],true,[],[i32(18),42],loud,"complete receive") { return false }
 split := [received(bytes[..7],[i32(18),42]),ReceiveStep{result:-1,code:C.EAGAIN},received(bytes[7..],[])]
 if !receive_case(run,split,true,[],[i32(18),42],loud,"partial frame EAGAIN") { return false }
 split_late := [received(bytes[..7],[]),ReceiveStep{result:-1,code:C.EINTR},received(bytes[7..],[i32(18),42])]
 if !receive_case(run,split_late,true,[],[i32(18),42],loud,"late rights EINTR") { return false }
 if !receive_case(run,[received(bytes,[])],false,[],[],loud,"missing rights") { return false }
 if !receive_case(run,[received(bytes[..7],[i32(18),42]),ReceiveStep{result:0}],false,[i32(18),42],[],loud,"EOF closes retained pair") { return false }
 if !receive_case(run,[received(bytes[..7],[i32(18),42]),ReceiveStep{result:-1,code:C.EIO}],false,[i32(18),42],[],loud,"read error closes retained pair") { return false }
 if !receive_case(run,[received(bytes[..7],[i32(18),42]),received(bytes[7..],[i32(20),43])],false,[i32(20),43,18,42],[],loud,"second rights closes both pairs") { return false }
 truncated := ReceiveStep{bytes:bytes,control:ancillary([i32(18),42],-1,0),flags:8,result:64}
 if !receive_case(run,[truncated],false,[i32(18),42],[],loud,"truncated receive closes rights") { return false }
 if !receive_case(run,[received(bytes[..7],[i32(18),42])],false,[i32(18),42],[],loud,"bounded incomplete receive") { return false }
 reset()
 p.poll_result = 0
 mut frame := [64]u8{}
 mut fds := [i32(-9),-9]!
 return check(!run(&frame[0],&fds[0]) && p.receive_index == 0 && fds == [i32(-1),-1]!,"poll timeout",loud)
}
fn ui_frame() []u8 {
 mut bytes := []u8{len:64}
 bytes[0] = `W`; bytes[1] = `S`; bytes[2] = `U`; bytes[3] = `I`; bytes[5] = 1
 bytes[15] = 1; bytes[16] = 2
 put_be32(mut bytes,48,64); put_be32(mut bytes,52,64); put_be32(mut bytes,56,256)
 return bytes
}
fn put_be32(mut bytes []u8,at int,value u32) {
 for i in 0 .. 4 { bytes[at+i] = u8(value >> (24-i*8)) }
}
fn descriptor_rejected(run Descriptors, frame []u8,loud bool,name string) bool {
 result := run(frame.data,18,42)
 return check(!result && ws.surface == unsafe { nil } && ws.input == -1 && ws_ui_mapping_size == 0 && p.closed.len == 0,name,loud)
}
fn descriptor_suite(run Descriptors,loud bool) bool {
 frame := ui_frame()
 reset(); ws.input = -1
 if !check(run(frame.data,18,42) && ws.surface != unsafe { nil } && ws.input == 42 && ws.width == 64 && ws.height == 64 && ws_ui_mapping_size == 32816 && p.mappings == 1 && p.fcntl_calls == [i32(3),3,1034,1,2,4] && p.closed.len == 0,"adopt validated descriptors",loud) { return false }
 for offset in [0,4,6,7,60] {
  reset(); ws.input = -1; mut bad := frame.clone(); bad[offset] = 99
  if !descriptor_rejected(run,bad,loud,"malformed frame") { return false }
 }
 for geometry in [[u32(63),64,252],[u32(4097),64,16388],[u32(64),63,256],[u32(64),4097,256],[u32(64),64,257]] {
  reset(); ws.input = -1; mut bad := frame.clone()
  put_be32(mut bad,48,geometry[0]); put_be32(mut bad,52,geometry[1]); put_be32(mut bad,56,geometry[2])
  if !descriptor_rejected(run,bad,loud,"bounded geometry") { return false }
 }
 for mode in 0 .. 16 {
  reset(); ws.input = -1
  match mode {
   0 { p.surface_flags = 0 }
   1 { p.input_flags = 1 }
   2 { p.seals = 2 }
   3 { p.surface_info.st_mode = 0x1000 }
   4 { p.surface_info.st_size-- }
   5 { p.input_info.st_mode = 0x8000 }
   6 { p.stat_error = 18 }
   7 { p.stat_error = 42 }
   8 { p.pread_result = 47 }
   9 { p.header.magic = 0 }
   10 { p.header.width = 65 }
   11 { p.header.buffer_size = 1 }
   12 { p.header.reader = 2 }
   13 { p.header.active = 1 }
   14 { p.fcntl_error = 2 }
   else { p.map_error = true }
  }
  if !descriptor_rejected(run,frame,loud,"invalid descriptor or surface:"+mode.str()) { return false }
 }
 reset(); ws.input = -1
 p.fcntl_error = 4
 return descriptor_rejected(run,frame,loud,"nonblocking setup failure")
}
fn input_suite(run Input,loud bool) bool {
 header := event_bytes(4,4)
 reset(); p.reads = [step(header[..3]),again()]
 if !check(run(voidptr(1)) && ws_ui_header_used == 3 && ws_ui_text_used == 0 && p.keys.len == 0 && ws.running,"partial header EAGAIN",loud) { return false }
 p.reads << [step(header[3..]),step([u8(65),0]),again()]
 if !check(run(voidptr(1)) && ws_ui_header_used == 24 && ws_ui_text_used == 2 && p.keys.len == 0 && ws.running,"partial binary key EAGAIN",loud) { return false }
 p.reads << [step([u8(66),255]),again()]
 if !check(run(voidptr(1)) && p.keys == [[u8(65),0,66,255]] && ws_ui_header_used == 0 && ws_ui_text_used == 0 && ws_ui_text.all(it == 0) && ws_ui_event.magic == 0 && ws.running,"complete and erase binary key",loud) { return false }
 reset(); p.reads = [interrupted(),step(event_bytes(2,0)),again()]
 if !check(run(voidptr(1)) && p.pointer.len == 1 && p.pointer[0].kind == 2 && ws.running,"header EINTR and pointer",loud) { return false }
 reset(); p.reads = [step(event_bytes(4,4096)),interrupted(),step([]u8{len:4096,init:7}),again()]
 if !check(run(voidptr(1)) && p.keys.len == 1 && p.keys[0].len == 4096 && ws_ui_text.all(it == 0),"maximum key and payload EINTR",loud) { return false }
 reset()
 for _ in 0 .. 40 { p.reads << interrupted() }
 for byte in header { p.reads << step([byte]) }
 p.reads << [step([u8(65),0,66,255]),again()]
 if !check(run(voidptr(1)) && p.read_index == 64 && ws_ui_header_used == 24 && ws_ui_text_used == 0 && p.keys.len == 0,"64 reads includes payload phase",loud) { return false }
 if !check(run(voidptr(1)) && p.keys == [[u8(65),0,66,255]] && ws_ui_text.all(it == 0),"resume payload after read budget",loud) { return false }
 for mode in 0 .. 8 {
  reset(); mut bad := event_bytes(4,0)
  unsafe {
   event := &WsEvent(bad.data)
   match mode {
    0 { event.magic = 0 }
    1 { event.kind = 0 }
    2 { event.kind = 6 }
    3 { event.length = 4097 }
    4 { event.kind = 2; event.length = 1 }
    5 { event.x = -1 }
    6 { event.x = 64 }
    else { event.y = 64 }
   }
  }
  p.reads = [step(bad),again()]
  if !check(!run(voidptr(1)) && p.keys.len == 0 && p.pointer.len == 0 && ws.running,"reject malformed input:"+mode.str(),loud) { return false }
 }
 for entries in [[eof()],[step(header[..7]),eof()],[step(header),step([u8(1)]),eof()],[ReadStep{result:-1,code:C.EIO}]] {
  reset(); p.reads = entries
  if !check(!run(voidptr(1)) && ws.running && p.keys.len == 0 && p.pointer.len == 0,"EOF/error preserves service",loud) { return false }
 }
 reset(); ws.activity = unsafe { nil }; p.reads = [step(event_bytes(3,0)),step(event_bytes(2,0))]
 if !check(run(voidptr(1)) && p.pointer.len == 1 && ws.running,"activity finish keeps service",loud) { return false }
 reset(); p.fail_push = true; p.reads = [step(event_bytes(4,4)),step([u8(1),2,3,4])]
 if !check(!run(voidptr(1)) && p.keys.len == 0 && ws_ui_text.all(it == 0) && ws_ui_header_used == 0 && ws_ui_text_used == 0 && ws.running,"failed local frame erases key",loud) { return false }
 reset(); p.dispatch_exception = true; p.reads = [step(event_bytes(4,4)),step([u8(1),2,3,4])]
 if !check(!run(voidptr(1)) && p.keys.len == 1 && p.exception && ws_ui_text.all(it == 0) && ws_ui_header_used == 0 && ws_ui_text_used == 0 && ws.running,"dispatch exception pops frame and erases key",loud) { return false }
 reset(); p.exception = true
 return check(!run(voidptr(1)) && p.read_index == 0 && ws.running,"pending JNI exception",loud)
}
fn live_session() {
 reset()
 ws_ui_session = 42
 ws_auth_slots = &WsAuthSlot{id:42,response:voidptr(50),bundle:voidptr(51),intent:voidptr(52)}
}
fn cancel_suite(run Cancel,loud bool) bool {
 live_session()
 run(voidptr(1))
 if !check(ws_ui_session == 0 && ws_auth_slots == unsafe { nil } && p.builders == [u64(42)] && p.sent == 1 && p.field_calls == 2 && p.builder_freed == 1 && p.slot_freed == [u64(42)] && p.drops == [voidptr(50),voidptr(51),voidptr(52)],"cancel detaches and releases original slot",loud) { return false }
 run(voidptr(1))
 if !check(p.sent == 1 && p.builders.len == 1 && p.builder_freed == 1 && p.slot_freed.len == 1,"cancel exact once",loud) { return false }
 live_session()
 tail := &WsAuthSlot{id:91,response:voidptr(59)}
 unsafe { ws_auth_slots.next = tail }
 ws_auth_slots = &WsAuthSlot{id:7,response:voidptr(57),next:ws_auth_slots}
 head := ws_auth_slots
 run(voidptr(1))
 if !check(ws_ui_session == 0 && ws_auth_slots == head && unsafe { head.next == tail } && p.slot_freed == [u64(42)] && p.sent == 1,"cancel middle retains unrelated sessions",loud) { return false }
 for mode in 0 .. 4 {
  live_session()
  match mode {
   0 { ws_ui_session = 0 }
   1 { ws_auth_ready = false }
   2 { ws_ui_session = 99 }
   else { ws_auth_handle = unsafe { nil } }
  }
  original := ws_auth_slots
  run(voidptr(1))
  expected_frees := if mode == 3 { [u64(42)] } else { []u64{} }
  unchanged := mode == 3 || ws_auth_slots == original
  if !check(ws_ui_session == 0 && unchanged && p.builders.len == 0 && p.sent == 0 && p.builder_freed == 0 && p.slot_freed == expected_frees,"cancel absent session or unavailable authority:"+mode.str(),loud) { return false }
 }
 live_session(); p.fail_builder = true
 run(voidptr(1))
 if !check(ws_ui_session == 0 && ws_auth_slots == unsafe { nil } && p.builders == [u64(42)] && p.sent == 0 && p.field_calls == 0 && p.builder_freed == 0 && p.slot_freed == [u64(42)],"failed response allocation releases slot",loud) { return false }
 live_session(); p.fail_fields = true
 run(voidptr(1))
 return check(ws_ui_session == 0 && ws_auth_slots == unsafe { nil } && p.sent == 0 && p.field_calls == 1 && p.builder_freed == 1 && p.slot_freed == [u64(42)],"failed error fields free builder",loud)
}
fn shutdown_suite(run Cancel,loud bool) bool {
 for retained in [false,true] {
  live_session()
  ws_ui_retained = retained
  ws.surface = unsafe { &p.header }; ws_ui_mapping_size = 32816
  ws.focused = voidptr(60); ws.pressed = voidptr(61); ws.dialog = voidptr(62); ws.dirty = true
  p.reads = [step(event_bytes(4,4)),step([u8(10),20]),eof()]
  if !check(!ws_service_ui_input(voidptr(1)) && ws.running && ws_ui_text_used == 2,"partial credential EOF before teardown",loud) { return false }
  run(voidptr(1))
  unmapped := p.unmaps == if retained {0} else {1}
  mapping := if retained { ws.surface != unsafe { nil } && ws_ui_mapping_size == 32816 } else { ws.surface == unsafe { nil } && ws_ui_mapping_size == 0 }
  if !check(ws.running && ws.service && !ws_ui_live && ws_ui_closing && ws.activity == unsafe { nil } && ws.input == -1 && ws_ui_channel == -1 && !ws.dirty && ws.focused == unsafe { nil } && ws.pressed == unsafe { nil } && ws.dialog == unsafe { nil } && p.closed == [i32(33),42] && p.lifecycle == ["vinixPerformPause","vinixPerformStop","vinixPerformDestroy"] && p.detached.len == 1 && p.sent == 1 && p.builder_freed == 1 && p.slot_freed == [u64(42)] && ws_ui_session == 0 && ws_ui_header_used == 0 && ws_ui_text_used == 0 && ws_ui_text.all(it == 0) && ws_ui_event.magic == 0 && unmapped && mapping,"EOF tears down UI and settles request",loud) { return false }
  run(voidptr(1))
  if !check(ws.running && p.closed.len == 2 && p.sent == 1 && p.builder_freed == 1 && p.slot_freed.len == 1 && p.lifecycle.len == 3 && p.background_count == 1 && p.unmaps == if retained {0} else {1},"teardown idempotence and background once",loud) { return false }
 }
 live_session(); p.complete_during_destroy = true
 run(voidptr(1))
 if !check(ws.running && p.results == 1 && p.sent == 0 && p.builders.len == 0 && p.builder_freed == 0 && p.slot_freed == [u64(42)] && ws_ui_session == 0 && ws_auth_slots == unsafe { nil },"real callback during destroy wins",loud) { return false }
 live_session(); p.exception = true; p.lifecycle_exception = true
 run(voidptr(1))
 if !check(ws.running && p.exception && p.throws == 1 && p.clear_count == 5 && p.lifecycle.len == 3 && p.background_count == 1 && p.sent == 1 && p.builder_freed == 1,"launch exception preserved around clean lifecycle",loud) { return false }
 live_session(); p.exception = true; p.cancel_exception = true
 run(voidptr(1))
 if !check(p.exception && !p.secondary_exception && p.throws == 1 && p.clear_count == 2 && p.drops.filter(it == voidptr(99)).len == 1 && p.sent == 1 && p.slot_freed == [u64(42)],"original cause restored after secondary cleanup exception",loud) { return false }
 live_session(); p.cancel_exception = true
 run(voidptr(1))
 if !check(p.exception && p.secondary_exception && p.throws == 0 && p.clear_count == 0 && p.drops.filter(it == voidptr(99)).len == 0,"secondary cleanup exception retained when no original exists",loud) { return false }
 live_session(); ws.back_count = 2; ws.back_stack[0] = voidptr(3); ws.back_stack[1] = voidptr(4)
 run(voidptr(1))
 if !check(ws.running && ws.back_count == 0 && ws.back_stack.all(it == unsafe { nil }) && p.lifecycle.len == 9 && p.detached.len == 3 && p.sent == 1,"all covered activities destroyed without resume",loud) { return false }
 live_session(); p.reentrant_shutdown = true
 run(voidptr(1))
 if !check(ws.running && p.reentered && p.lifecycle.len == 3 && p.closed.len == 2 && p.sent == 1 && p.builder_freed == 1 && p.slot_freed.len == 1,"reentrant finish destroys and settles once",loud) { return false }
 live_session(); ws.service = false
 run(voidptr(1))
 return check(!ws.running && p.sent == 1 && ws_ui_session == 0,"nonservice teardown terminates loop",loud)
}
'

fn ui_mutations(name string, source string) []string {
	return match name {
		'ws_ui_rights' {
			[
				source.replace('flags & 0x28 == 0', 'true'),
				source.replace('valid && used == 2 && messages == 1', 'valid && used >= 2 && messages == 1'),
				source.replace(' && messages == 1', ''),
				source.replace('probe_close(received[i])', '_ = received[i]'),
			]
		}
		'ws_ui_receive' {
			[
				source.replace('defer { if !accepted { ws_ui_close_pair(fds) } }', ''),
				source.replace('if fds[0] >= 0 { ws_ui_close_pair(&incoming[0]); return false }', ''),
				source.replace('0 .. 64', '0 .. 1'),
				source.replace('iov_base: &frame[received]', 'iov_base: &frame[0]'),
			]
		}
		'ws_ui_descriptors' {
			[
				source.replace(' || seals & 6 != 6', ''),
				source.replace(' || surface_info.st_size != i64(length)', ''),
				source.replace('|| header.magic != 0x31534656', '|| false'),
				source.replace('probe_fcntl(input_fd, 4, input_flags | 0x800) != 0', 'false'),
			]
		}
		'ws_ui_cancel' {
			[
				source.replace('ws_ui_session = 0', ''),
				source.replace('ws_auth_free(builder)', ''),
				source.replace('ws_auth_slots = node.next', ''),
				source.replace('probe_pthread_mutex_unlock(&ws_auth_mutex)', ''),
			]
		}
		'ws_service_ui_shutdown' {
			[
				source.replace('ws.running = ws.service', 'ws.running = false'),
				source.replace('C.memset(&ws_ui_text[0], 0, 4096)', ''),
				source.replace('ws_ui_cancel(e)', ''),
				source.replace(' && !ws_ui_retained', ''),
				source.replace('ws_uid_lifecycle(e, 300)', ''),
				source.replace('ws_ui_clear_exception(e)\n\t\t\t// Clear each root', 'ws_ui_clear_exception(e)\n\t\t\tws_ui_cancel(e)\n\t\t\t// Clear each root'),
				source.replace('ws_ui_clear_exception(e)\n\t\t\t\tWsApplicationThrow', 'WsApplicationThrow'),
			]
		}
		else {
			[
				source.replace('if code == C.EAGAIN { return true }', 'if code == C.EAGAIN { return false }'),
				source.replace('ws_ui_header_used += u32(n)', 'ws_ui_header_used = u32(n)'),
				source.replace('ws_ui_text_used += u32(n)', 'ws_ui_text_used = u32(n)'),
				source.replace('ws_ui_event.length > 4096', 'ws_ui_event.length > 8192'),
				source.replace('C.memset(&ws_ui_text[0], 0, 4096)', ''),
				source.replace('if n == 0 ||', 'if n == 0 { ws.running = false }; if n == 0 ||'),
				source.replace('if reads == 64 { return true }', ''),
			]
		}
	}
}
