// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production service argv parser with deterministic trust/syscall
// adapters. This host check covers the native ABI handoff, not ART execution.
module main

import crypto.sha256
import json2
import os

fn entry_block(source string, name string) !string {
	start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
	end := source[start..].index('\n}') or { return error('unclosed ' + name) }
	return source[start..start + end + 2]
}

fn entry_handoff(source string) bool {
	entry_main := entry_block(source, 'main') or { return false }
	parse := entry_main.index('selected, fd, selected_ui := service_launch()') or { return false }
	load := entry_main.index('C.dlopen(') or { return false }
	clear := entry_main.index("os.unsetenv('VINIX_ANDROID_AUTHENTICATOR_FD')") or { return false }
	return clear < parse && parse < load
		&& source.contains('type NativeServiceMain = fn (&char, &char, &char, &char, &char, i32, i32) i32')
		&& entry_main.contains('control_fd = fd') && entry_main.contains('ui_fd = selected_ui')
		&& entry_main.contains('exit(int(entry(root.str, os.args[1].str, launch.package_name.str, launch.service.str, launch.action.str, i32(control_fd), i32(ui_fd))))')
}

fn entry_implementation_abi(source string) bool {
	return source.contains("@[export: 'vinix_android_native_service_main']\nfn ws_service_main(root &char, apk &char, package_name &char, service &char, action &char, control_fd i32, ui_fd i32) i32 {")
}

struct EntryReceipt {
	argv   []string
	status int
	output string
}

struct EntryEvidence {
	scope                 string
	source_sha256         string
	implementation_sha256 string
	source_revision       string
	compiler              string
	compiler_sha256       string
	compile               EntryReceipt
	run                   EntryReceipt
}

fn main() {
	assert os.args.len in [2, 3], 'usage: check-native-entry-ui OUTPUT_DIR [REPO]'
	repo := if os.args.len == 3 { os.real_path(os.args[2]) } else { os.getwd() }
	work := os.abs_path(os.args[1])
	assert !os.exists(work), 'output directory must be new'
	assert work != repo && !work.starts_with(repo + '/'), 'keep generated evidence outside Git'
	os.mkdir_all(work)!
	source := os.read_file(repo + '/build-support/android/native-entry.v')!
	implementation := os.read_file(repo + '/build-support/android/nativews/headless.v')!
	assert entry_handoff(source), 'service channels must be verified before library loading and passed directly through the typed ABI'
	assert entry_implementation_abi(implementation), 'native service export must match entry NativeServiceMain, including final ui_fd i32'
	for mutation in [implementation.replace(', ui_fd i32) i32', ') i32'),
		implementation.replace(', ui_fd i32) i32', ', ui_fd i64) i32')] {
		assert mutation != implementation && !entry_implementation_abi(mutation), 'service implementation ABI guard accepted a mismatch'
	}
	for mutation in [
		source.replace('i32, i32) i32', 'i32) i32'),
		source.replace('ui_fd = selected_ui', 'ui_fd = control_fd'),
		source.replace('i32(control_fd), i32(ui_fd)', 'i32(control_fd), i32(control_fd)'),
		source.replace("os.unsetenv('VINIX_ANDROID_AUTHENTICATOR_FD')", ''),
		source.replace('selected, fd, selected_ui := service_launch()',
			'unsafe { C.dlopen(nil, 0) }\n\t\tselected, fd, selected_ui := service_launch()'),
	] {
		assert mutation != source && !entry_handoff(mutation), 'handoff checker accepted a negative mutation'
	}
	mut parser := entry_block(source, 'service_launch')!
	for name in ['load', 'verify_service_frame', 'verify_root_channel'] {
		parser = parser.replace('nativeaccountauth.' + name, 'probe_' + name)
	}
	parser = parser.replace('nativeaccountauth.ServiceLaunch', 'ProbeServiceLaunch')
		.replace('os.args', 'probe_arguments')
		.replace('os.getenv_opt', 'probe_getenv_opt').replace('os.setenv', 'probe_setenv')
		.replace('C.getuid()', 'probe_getuid()').replace('C.getgid()', 'probe_getgid()')
		.replace('C.fcntl', 'probe_fcntl').replace('C.F_GETFD', '1')
		.replace('C.F_SETFD', '2').replace('C.FD_CLOEXEC', '1')
	type_line := source.split_into_lines().filter(it.starts_with('type NativeServiceMain = '))
	assert type_line.len == 1
	implementation_line := implementation.split_into_lines().filter(it.starts_with('fn ws_service_main('))
	assert implementation_line.len == 1
	call_line := source.split_into_lines().filter(it.contains('exit(int(entry(root.str, os.args[1].str, launch.package_name.str'))
	assert call_line.len == 1
	call := call_line[0].trim_space().replace('exit(int(', 'return int(')
		.replace('os.args[1]', 'apk')
	// Remove only exit's outer closing parenthesis. The production call and
	// NativeServiceMain type are compiled and exercised against the ABI spy.
	assert call.ends_with(')))')
	invoke := '\nfn invoke_entry(entry NativeServiceMain, root string, apk string, launch ProbeServiceLaunch, control_fd int, ui_fd int) int {\n' + call[..call.len - 1] + '\n}\n'
	os.write_file(work + '/input-native-entry.v', source)!
	os.write_file(work + '/input-nativews-headless.v', implementation)!
	model := entry_model.replace('@ENTRY_SERVICE_SIGNATURE@', implementation_line[0].replace('fn ws_service_main(', 'fn abi_spy('))
	os.write_file(work + '/main.v', model + '\n' + type_line[0] + '\n' + parser + invoke + entry_cases)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	compile_argv := [compiler, '-w', '-enable-globals', '-cc', 'cc', '-o', work + '/probe',
		work + '/main.v']
	compiled := os.exec(compile_argv)
	os.write_file(work + '/compile.log', compiled.output)!
	if compiled.exit_code != 0 { panic(compiled.output) }
	run_argv := [work + '/probe']
	ran := os.exec(run_argv)
	os.write_file(work + '/run.log', ran.output)!
	if ran.exit_code != 0 { panic(ran.output) }
	assert ran.output.trim_space() == 'NATIVE-ENTRY-UI-PASS canonical distinct root-peer order registry cloexec failures direct-abi'
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(work + '/build.json', json2.encode(EntryEvidence{
		scope:                 'Extracted production service_launch and entry ABI host contract; no ART or guest execution.'
		source_sha256:         sha256.sum(source.bytes()).hex()
		implementation_sha256: sha256.sum(implementation.bytes()).hex()
		source_revision:       revision.output.trim_space()
		compiler:              compiler
		compiler_sha256:       sha256.sum(os.read_bytes(compiler)!).hex()
		compile:               EntryReceipt{compile_argv, compiled.exit_code, compiled.output}
		run:                   EntryReceipt{run_argv, ran.exit_code, ran.output}
	}, prettify: true))!
	println(ran.output.trim_space())
	println('NATIVE-ENTRY-UI-HANDOFF-PASS negative-mutations=7 production-service-signature')
}

const entry_model = '
module main
import strconv
struct ProbeServiceLaunch { package_name string service string action string }
struct ProbeRegistry {}
struct ProbePeer { uid u32 }
struct EntryProbe {
mut:
 registry_present bool = true
 registry_error bool
 frame_error bool
 peer_uid map[int]u32
 peer_error int = -1
 get_error int = -1
 set_error int = -1
 flags map[int]i32
 trace []string
 auth_env string
 uid u32 = 10001
 gid i32 = 10002
}
__global ep = EntryProbe{}
__global probe_arguments []string
fn probe_getenv_opt(name string) ?string {
 assert name == "VINIX_ANDROID_ACCOUNT_REGISTRY"
 ep.trace << "registry-env"
 if !ep.registry_present { return none }
 return "/root/registry"
}
fn probe_load(path string) !ProbeRegistry {
 assert path == "/root/registry"; ep.trace << "registry-load"
 if ep.registry_error { return error("untrusted registry") }
 return ProbeRegistry{}
}
fn probe_getuid() u32 { return ep.uid }
fn probe_getgid() i32 { return ep.gid }
fn probe_verify_service_frame(fd int, registry ProbeRegistry, apk string, uid u32, gid u32) !ProbeServiceLaunch {
 assert apk == "/registered.apk" && uid == ep.uid && gid == u32(ep.gid)
 ep.trace << "service:" + fd.str()
 if ep.frame_error || uid != 10001 || gid != 10002 { return error("unregistered service identity") }
 return ProbeServiceLaunch{"com.example.origin","com.example.origin.Authenticator","android.accounts.AccountAuthenticator"}
}
fn probe_verify_root_channel(fd int) !ProbePeer {
 ep.trace << "peer:" + fd.str()
 if fd == ep.peer_error || fd !in ep.peer_uid || ep.peer_uid[fd] != 0 { return error("not root Unix peer") }
 return ProbePeer{ep.peer_uid[fd]}
}
fn probe_fcntl(fd i32, operation i32, flags ...i32) i32 {
 ep.trace << (if operation == 1 { "get:" } else { "set:" }) + fd.str()
 if operation == 1 {
  assert flags.len == 0
  if fd == ep.get_error { return -1 }
  return ep.flags[int(fd)]
 }
 assert operation == 2 && flags.len == 1 && flags[0] == ep.flags[int(fd)] | 1
 if fd == ep.set_error { return -1 }
 ep.flags[int(fd)] = flags[0]
 return 0
}
fn probe_setenv(name string, value string, overwrite bool) {
 assert name == "VINIX_ANDROID_AUTHENTICATOR_FD" && overwrite
 ep.trace << "auth-env:" + value; ep.auth_env = value
}
fn reset_entry(arguments []string) {
 ep = EntryProbe{peer_uid:{4:u32(0),5:u32(0)},flags:{3:i32(8),4:i32(16),5:i32(32)}}
 probe_arguments = ["native-entry","/registered.apk"]
 probe_arguments << arguments
}
fn rejected(arguments []string) {
 reset_entry(arguments)
 service_launch() or { return }
 panic("accepted malformed service argv: " + arguments.str())
}
fn reject_current() {
 service_launch() or { return }
 panic("accepted rejected trust/syscall result")
}
@ENTRY_SERVICE_SIGNATURE@
 unsafe {
  assert cstring_to_vstring(root) == "/runtime" && cstring_to_vstring(apk) == "/registered.apk"
  assert cstring_to_vstring(package_name) == "com.example.origin"
  assert cstring_to_vstring(service) == "com.example.origin.Authenticator"
  assert cstring_to_vstring(action) == "android.accounts.AccountAuthenticator"
 }
 assert control_fd == 3 && ui_fd == 5
 return 73
}
'

const entry_cases = '
fn main() {
 base := ["--service-fd","3"]
 auth := ["--service-fd","3","--authenticator-fd","4"]
 full := ["--service-fd","3","--authenticator-fd","4","--ui-fd","5"]
 reset_entry(base)
 launch, lifetime, ui := service_launch()!
 assert lifetime == 3 && ui == -1 && launch.package_name == "com.example.origin"
 assert ep.auth_env == "" && ep.flags[3] == 9
 assert ep.trace == ["registry-env","registry-load","service:3","get:3","set:3"]
 reset_entry(auth)
 _, auth_lifetime, absent_ui := service_launch()!
 assert auth_lifetime == 3 && absent_ui == -1 && ep.auth_env == "4" && ep.flags[4] == 17
 assert ep.trace == ["registry-env","registry-load","service:3","get:3","set:3","peer:4","get:4","set:4","auth-env:4"]
 reset_entry(full)
 selected, control, selected_ui := service_launch()!
 assert control == 3 && selected_ui == 5 && ep.flags[3] == 9 && ep.flags[4] == 17 && ep.flags[5] == 33
 assert ep.trace == ["registry-env","registry-load","service:3","get:3","set:3","peer:4","get:4","set:4","auth-env:4","peer:5","get:5","set:5"]
 assert invoke_entry(abi_spy,"/runtime","/registered.apk",selected,control,selected_ui) == 73
 for arguments in [
  []string{}, ["--service-fd"], ["--ui-fd","5"], ["--service-fd","3","--ui-fd","5"],
  ["--service-fd","3","--authenticator-fd","4","--ui-fd"],
  ["--service-fd","3","--authenticator-fd","4","--ui-fd","5","extra","6"],
  ["--service-fd","3","--ui-fd","5","--authenticator-fd","4"],
  ["--service-fd","3","--authenticator-fd","4","--authenticator-fd","5"],
  ["--service-fd","3","--authenticator-fd","3"],
  ["--service-fd","3","--authenticator-fd","4","--ui-fd","3"],
  ["--service-fd","3","--authenticator-fd","4","--ui-fd","4"],
 ] { rejected(arguments) }
 for value in ["", "0", "2", "-1", "+3", "03", " 3", "3 ", "3x", "3\x00", "2147483648", "4294967299", "999999999999999999999999999999"] {
  rejected(["--service-fd",value])
  rejected(["--service-fd","3","--authenticator-fd",value])
  rejected(["--service-fd","3","--authenticator-fd","4","--ui-fd",value])
 }
 reset_entry(["--service-fd","2147483647"])
 _, max_fd, _ := service_launch()!; assert max_fd == 2147483647
 reset_entry(["--service-fd","3","--authenticator-fd","2147483647"])
 ep.peer_uid[2147483647] = 0
 service_launch()!; assert ep.auth_env == "2147483647"
 reset_entry(["--service-fd","3","--authenticator-fd","4","--ui-fd","2147483647"])
 ep.peer_uid[2147483647] = 0
 _, _, max_ui := service_launch()!; assert max_ui == 2147483647
 reset_entry(full); ep.registry_present = false; reject_current(); assert ep.trace == ["registry-env"]
 reset_entry(full); ep.registry_error = true; reject_current(); assert ep.trace == ["registry-env","registry-load"]
 reset_entry(full); ep.frame_error = true; reject_current(); assert ep.trace == ["registry-env","registry-load","service:3"]
 reset_entry(full); ep.uid = 10003; reject_current(); assert ep.trace == ["registry-env","registry-load","service:3"]
 reset_entry(full); ep.gid = 10003; reject_current(); assert ep.trace == ["registry-env","registry-load","service:3"]
 for fd in [4,5] {
  reset_entry(full); ep.peer_uid[fd] = 10001; reject_current()
  assert !("get:" + fd.str() in ep.trace)
  reset_entry(full); ep.peer_error = fd; reject_current()
  assert !("get:" + fd.str() in ep.trace)
 }
 for fd in [3,4,5] {
  reset_entry(full); ep.get_error = fd; reject_current()
  assert !("set:" + fd.str() in ep.trace)
  reset_entry(full); ep.set_error = fd; reject_current()
  assert ep.flags[fd] & 1 == 0
 }
 println("NATIVE-ENTRY-UI-PASS canonical distinct root-peer order registry cloexec failures direct-abi")
}
'
