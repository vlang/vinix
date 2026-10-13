// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import hosttest
import net.unix
import os
import qmpclient
import sourcecommand
import sourcefixture
import time

struct Interrupt {
	ready chan bool
	signal i32
}

fn interrupt_child(pid int, context voidptr) ! {
	state := unsafe { &Interrupt(context) }
	select {
		_ := <-state.ready {}
		5 * time.second { return error('QMP child did not reach its signal checkpoint') }
	}
	if C.kill(i32(pid),state.signal) != 0 { return os.error_posix() }
}

fn interrupt_peer(mut listener unix.StreamListener, ready chan bool) ! {
	listener.set_accept_timeout(5*time.second)
	listener.wait_for_accept()!
	mut connection := listener.accept()!
	defer {connection.close() or {}}
	connection.write_string('native greeting\n')!
	assert line(mut connection)! == '{"execute":"qmp_capabilities"}'
	ready <- true
	// A native channel checkpoint ensures the signal arrives after the
	// child's handlers and owned socket are active, regardless of startup.
	time.sleep(300*time.millisecond)
}

fn line(mut connection unix.StreamConn) !string {
	mut bytes := []u8{}
	mut byte := []u8{len:1}
	for {
		if connection.read(mut byte)! == 0 { return error('socket EOF') }
		if byte[0] == `\n` { return bytes.bytestr() }
		bytes << byte[0]
	}
	return error('socket EOF')
}

const large_request = '{"execute":"query-status","id":1234567890123456789012345678901234567890,"extra":[true,null,-184467440737095516161,"日本語"]}'

fn peer(mut listener unix.StreamListener, scenario string) ![]string {
	listener.set_accept_timeout(5*time.second)
	listener.wait_for_accept()!
	mut connection := listener.accept()!
	defer {connection.close() or {}}
	if scenario == 'bad-greeting' { connection.write([u8(255),10])!;return []string{} }
	connection.write_string('native greeting 日本語, without JSON\r\n')!
	mut requests := [line(mut connection)!]
	connection.write_string('{"event":"READY"}\n{"error":42}\n')!
	if scenario == 'empty' { return requests }
	requests << line(mut connection)!
	if scenario == 'deadline' { time.sleep(300*time.millisecond);return requests }
	match scenario {
		'ok' { connection.write_string('{"event":"STOP"}\n{"return":{"counter":123456789012345678901234567890},"id":"unrelated"}\n')! }
		'error' { connection.write_string('{"error":{"desc":"denied 日本語"}}\n')! }
		'fallback' { connection.write_string('{"error":{"class":"GenericError"}}\n')! }
		'null' { connection.write_string('{"error":{"desc":null}}\n')! }
		'integer' { connection.write_string('{"error":{"desc":7}}\n')! }
		'boolean' { connection.write_string('{"error":{"desc":false}}\n')! }
		'blank-error' { connection.write_string('{"error":{"desc":""}}\n')! }
		'bad-json' { connection.write_string('{invalid}\n')! }
		'bad-utf8' { connection.write([u8(255),10])! }
		'non-object' { connection.write_string('["return"]\n')! }
		'eof' {}
		else { return error('unknown peer scenario') }
	}
	return requests
}

fn check(frontend string, trimmer string, directory string) ! {
	assert qmpclient.normalize_request(' { "execute" : "query-status", "id" : 1234567890123456789012345678901234567890, "extra" : [ true, null, -184467440737095516161, "日本語" ] } ')! == large_request
	assert qmpclient.normalize_request('{"same":1,"same":9007199254740993}')! == '{"same":9007199254740993}'
	assert qmpclient.normalize_request('{"text":"line\\n\\t\\u65e5","decimal":-0.5e+4}')! == '{"text":"line\\n\\t日","decimal":-0.5e+4}'
	for invalid in ['[]','true','{"n":01}','{"n":1} junk','{"n":NaN}','{"broken":"'+[u8(255)].bytestr()+'"}'] {
		mut rejected := false
		qmpclient.normalize_request(invalid) or { rejected=true;'' }
		assert rejected, invalid
	}
	// Socket names stay below Darwin's 104-byte limit, independent of caches.
	os.setenv('TMPDIR','/private/tmp',true)
	short := hosttest.work_dir('','qmp-shell-')!
	defer {hosttest.remove_work_dir(short) or {}}
	baseline := os.ls('/dev/fd')!.len
	for scenario in ['ok','error','fallback','null','integer','boolean','blank-error','bad-json','bad-utf8','non-object','eof','bad-greeting','empty','deadline'] {
		eprintln('CHECK QMP socket '+scenario)
		path := short+'/qmp'
		mut listener := unix.listen_stream(path)!
		server := spawn peer(mut listener,scenario)
		requests := if scenario == 'empty' {[]string{}} else {[large_request,'{"execute":"must-not-run-after-error"}']}
		// Every non-error scenario sends only one request; error and zero-exit
		// statuses must stop before any following request can be sent.
		selected := if scenario == 'ok' {requests[..1]} else {requests}
		mut failed := false
		mut result := qmpclient.BatchExit{}
		if scenario=='deadline' {
			mut monitor := qmpclient.connect_text(path,time.sys_mono_now()+u64(5*time.second),unsafe {nil})!
			monitor.set_deadline(time.sys_mono_now()+u64(150*time.millisecond))
			result = monitor.exchange_json(large_request) or {
				failed = true
				assert err.msg().contains('deadline')
				qmpclient.BatchExit{}
			}
			monitor.close()
		} else {
			result = qmpclient.batch(path,selected,time.sys_mono_now()+u64(5*time.second),unsafe {nil}) or {failed=true;qmpclient.BatchExit{}}
		}
		seen := server.wait() or { return error('QMP peer '+scenario+': '+err.msg()) }
		listener.close()!
		os.rm(path) or {}
		assert failed == (scenario in ['bad-json','bad-utf8','non-object','eof','bad-greeting','deadline']), scenario
		if scenario !in ['bad-greeting','deadline'] { assert seen[0] == '{"execute":"qmp_capabilities"}' }
		if seen.len == 2 {assert seen[1]==large_request}
		assert seen.len <= 2
		match scenario {
			'error' {assert result.is_error && result.status==1 && result.print_error && result.message=='denied 日本語'}
			'fallback' {assert result.message=='QMP error' && result.status==1}
			'null','boolean' {assert result.is_error && result.status==0 && !result.print_error}
			'integer' {assert result.status==7 && !result.print_error}
			'blank-error' {assert result.status==1 && result.print_error && result.message==''}
			else {}
		}
		assert os.ls('/dev/fd')!.len==baseline
	}
	// Public CLI error output and exit values, including an empty diagnostic,
	// come from a real owned child instead of an implementation-only model.
	for scenario in ['ok','error','fallback','null','integer','boolean','blank-error'] {
		eprintln('CHECK QMP CLI '+scenario)
		mut listener:=unix.listen_stream(short+'/qmp')!
		server:=spawn peer(mut listener,scenario)
		output:=sourcecommand.capture_full([frontend,'qmp',short+'/qmp',large_request],os.environ(),10,65536,cachecli.cancelled)!
		server.wait()!
		listener.close()!
		os.rm(short+'/qmp') or {}
		assert output.stdout==''
		assert output.status==match scenario {'error','fallback','blank-error'{1}'integer'{7}else{0}}
		assert output.stderr==match scenario {'error'{'denied 日本語\n'}'fallback'{'QMP error\n'}'blank-error'{'\n'}else{''}}
	}
	for _ in 0..100 {
		qmpclient.batch(short+'/missing',[]string{},0,unsafe {nil}) or {}
		assert os.ls('/dev/fd')!.len==baseline
	}
	for signal in [i32(2),15] {
		eprintln('CHECK QMP signal '+signal.str())
		mut listener:=unix.listen_stream(short+'/qmp')!
		ready := chan bool{cap:1}
		server:=spawn interrupt_peer(mut listener,ready)
		state := Interrupt{ready:ready,signal:signal}
		log:=short+'/signal-'+signal.str()
		result:=sourcecommand.run_logged_owned([frontend,'qmp',short+'/qmp',large_request],os.environ(),
			cachecli.cancelled,log,false,'',interrupt_child,unsafe {&state},0)!
		server.wait()!
		listener.close()!
		os.rm(short+'/qmp') or {}
		assert result.status == 128+int(signal) && os.read_file(log)!.contains('QMP interrupted')
		assert os.ls('/dev/fd')!.len==baseline
	}
	os.mkdir_all(directory)!
	for index,text in ['start\n# Vinix execinfo compatibility\ntail','no marker\n','one\r\ntwo\r# Vinix execinfo compatibilitytail','\xef\xbb\xbfstart\n# Vinix execinfo compatibility'] {
		input:=directory+'/cmake-'+index.str()
		os.write_file(input,text)!
		output:=sourcecommand.capture_full([trimmer,input],os.environ(),10,65536,cachecli.cancelled)!
		assert output.status==0 && output.stdout=='' && output.stderr==''
		assert os.read_file(input)! == text.replace('\r\n','\n').replace('\r','\n').all_before('# Vinix execinfo compatibility')
	}
	bad:=directory+'/invalid'
	os.write_file_array(bad,[u8(255)])!
	output:=sourcecommand.capture_full([trimmer,bad],os.environ(),10,65536,cachecli.cancelled)!
	assert output.status!=0 && os.read_bytes(bad)! == [u8(255)]
	assert sourcefixture.trim_cmake('unchanged')=='unchanged'
	println('PASS exact JSON, native QMP/CLI terminal/error/event/UTF-8/EOF/deadline policies, descriptor retirement and CMake source edits')
}

fn main() {
	guard:=cachecli.own_commands()
	defer {guard.close()}
	if os.args.len != 4 {eprintln('expected FRONTEND TRIMMER NEW_DIRECTORY');exit(1)}
	check(os.args[1],os.args[2],os.args[3]) or {eprintln(err);exit(1)}
}
