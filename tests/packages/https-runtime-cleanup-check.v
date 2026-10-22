// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import crypto.sha256

#include <errno.h>
#include <signal.h>

fn C.kill(int, int) int

fn literal(text string) string {
	return "'" + text.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"
}

fn command(args []string) !int {
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.run()
	defer {
		if child.is_alive() { child.signal_kill() }
		child.wait()
		child.close()
	}
	start := time.now()
	for child.is_alive() {
		if time.since(start) > 180 * time.second {
			return error('cleanup control command exceeded 180 seconds')
		}
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	return child.code
}

fn check() ! {
	if os.args.len != 2 { return error('usage: https-runtime-cleanup-check REPORT_PATH') }
	root := os.dir(os.dir(os.dir(@FILE)))
	source_path := root + '/tests/packages/https-runtime-check.v'
	source := os.read_file(source_path)!
	ready := "\tbase := ready(work + '/ready', mut server)!\n"
	close := '\t\tserver.close()\n\t}'
	root_line := '\troot := os.dir(os.dir(os.dir(@FILE)))'
	if !source.contains(ready) || !source.contains(close) || !source.contains(root_line) {
		return error('controller lifecycle changed; review cleanup instrumentation')
	}
	work := os.join_path(os.temp_dir(), 'vinix-tls-cleanup-' + os.getpid().str() + '-' + time.now().unix_milli().str())
	os.mkdir_all(work)!
	state := work + '/state'
	mut server_pid := 0
	defer {
		if server_pid <= 0 { server_pid = (os.read_file(state + '/cleanup-pid') or { '0' }).int() }
		if server_pid > 0 && C.kill(server_pid, 0) == 0 { C.kill(server_pid, C.SIGKILL) }
		os.rmdir_all(work) or {}
	}
	variant := source.replace_once(root_line, '\troot := ' + literal(root))
		.replace_once(ready, ready + "\tos.write_file(work + '/cleanup-pid', server.pid.str())!\n" +
			"\trun('cleanup-refusal', [os.find_abs_path_of_executable('false')!], work, work + '/server')!\n")
		.replace_once(close, '\t\tserver.close()\n' +
			"\t\tif cleanup_reaped(server.pid) { os.write_file(work + '/cleanup-proof', 'server reaped PASS\\n') or {} }\n\t}") +
		'\n#include <errno.h>\n#include <sys/wait.h>\nfn C.waitpid(int, &int, int) int\n' +
		'fn cleanup_reaped(pid int) bool {\n\tmut status := 0\n' +
		'\treturn C.waitpid(pid, unsafe { &status }, C.WNOHANG) == -1 && C.errno == C.ECHILD\n}\n'
	variant_source := work + '/controller.v'
	os.write_file(variant_source, variant)!
	v := os.find_abs_path_of_executable(os.getenv_opt('V') or { 'v' })!
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	binary := work + '/controller'
	if command([v, '-nocache', '-no-skip-unused', '-cc', 'clang', '-path',
		'@vlib|@vmodules|' + root + '|' + root + '/tools/accounts|' + root + '/tests/packages|' + root + '/tests/hardware-platform',
		'-o', binary, variant_source])! != 0 {
		return error('cleanup controller variant did not compile')
	}
	code := command([binary, 'host', state])!
	server_pid = os.read_file(state + '/cleanup-pid')!.int()
	if server_pid <= 0 { return error('cleanup control did not observe a server PID') }
	if C.kill(server_pid, 0) != -1 || C.errno != C.ESRCH {
		return error('failed qualification left its TLS server alive')
	}
	if os.read_file(state + '/cleanup-proof')! != 'server reaped PASS\n' {
		return error('failed qualification did not reap its TLS server')
	}
	if code != 1 || os.exists(state + '/qualification.json') {
		return error('failed qualification admitted a receipt or unexpected exit status')
	}
	if os.read_file(state + '/cleanup-refusal.txt')! != '' {
		return error('failure control command produced unexpected output')
	}
	report := 'Controller source SHA256 ' + sha256.sum(source.bytes()).hex() + '\n' +
		'Compiler ' + v + ' SHA256 ' + sha256.sum(os.read_bytes(v)!).hex() + '\n' +
		'Actual check()/main failure: child exit 1 after TLS listener readiness PASS\n' +
		'Actual server-owner defer: kill(pid,0)=ESRCH; same-parent waitpid(pid,WNOHANG)=ECHILD PASS\n' +
		'Failed qualification emits no receipt PASS\n' +
		'GUEST TLS controller failure cleanup PASS\n'
	os.mkdir_all(os.dir(os.abs_path(os.args[1])))!
	os.write_file(os.args[1], report)!
	print(report)
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
