// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module guestvalidation

import cachecli
import net
import os
import sourcecommand
import strconv
import math
import sync
import time

pub const codex_response = 'event: response.created\ndata: {"type":"response.created","response":{"id":"resp-vinix"}}\n\nevent: response.output_item.done\ndata: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","id":"msg-vinix","content":[{"type":"output_text","text":"VINIX CODEX LOOPBACK PASS"}]}}\n\nevent: response.completed\ndata: {"type":"response.completed","response":{"id":"resp-vinix","usage":{"input_tokens":0,"input_tokens_details":null,"output_tokens":0,"output_tokens_details":null,"total_tokens":0}}}\n\n'
pub const claude_response = 'event: message_start\ndata: {"type":"message_start","message":{"id":"msg_vinix","type":"message","role":"assistant","model":"claude-sonnet-4-5","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}\n\nevent: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\nevent: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"VINIX CLAUDE LOOPBACK PASS"}}\n\nevent: content_block_stop\ndata: {"type":"content_block_stop","index":0}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":7}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n'

struct SmokeServer {
	claude   bool
	deadline u64
mut:
	mutex        sync.Mutex
	stopped      bool
	expired      bool
	requests     int
	request_path string
	failure      string
}

__global active_smoke &SmokeServer

fn smoke_cancelled() bool {
	if cachecli.cancelled() { return true }
	if active_smoke == unsafe { nil } { return false }
	mut server := active_smoke
	server.mutex.lock()
	expired := server.expired
	server.mutex.unlock()
	return expired
}

fn (mut server SmokeServer) finished() bool {
	server.mutex.lock()
	defer { server.mutex.unlock() }
	if time.sys_mono_now() >= server.deadline { server.expired = true }
	return server.stopped || server.expired
}

fn (mut server SmokeServer) stop() {
	server.mutex.lock()
	server.stopped = true
	server.mutex.unlock()
}

fn smoke_read(mut connection net.TcpConn, mut server SmokeServer, mut bytes []u8, wanted int, header bool) ! {
	mut buffer := []u8{len: 65536}
	for (header && !bytes.bytestr().contains('\r\n\r\n')) || (!header && bytes.len < wanted) {
		if server.finished() { return error('loopback request deadline') }
		count := connection.read(mut buffer) or {
			if err.code() == net.err_timed_out_code { continue }
			return err
		}
		if count == 0 { return error('incomplete loopback request') }
		bytes << buffer[..count]
		if bytes.len > 64 * 1024 * 1024 { return error('loopback request exceeds limit') }
	}
}

fn smoke_reply(mut connection net.TcpConn, status int, content_type string, body string, head bool) ! {
	header := 'HTTP/1.0 ${status} ' + if status == 200 { 'OK' } else { 'Not Found' } + '\r\nContent-Type: ${content_type}\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n'
	connection.write_string(header)!
	if !head { connection.write_string(body)! }
}

fn smoke_request(mut connection net.TcpConn, mut server SmokeServer) ! {
	connection.set_read_timeout(200 * time.millisecond)
	connection.set_write_timeout(time.second)
	mut bytes := []u8{}
	smoke_read(mut connection, mut server, mut bytes, 0, true)!
	end := (bytes.bytestr().index('\r\n\r\n') or { return error('missing HTTP header boundary') }) + 4
	headers := bytes[..end].bytestr().split('\r\n')
	request := headers[0].fields()
	if request.len < 2 { return error('malformed loopback request') }
	mut length := 0
	for row in headers[1..] {
		if row.to_lower().starts_with('content-length:') {
			length = strconv.atoi(row.all_after(':').trim_space())!
		}
	}
	if length < 0 || length > 64 * 1024 * 1024 - end {
		return error('invalid loopback content length')
	}
	smoke_read(mut connection, mut server, mut bytes, end + length, false)!
	if request[0] == 'POST' {
		server.mutex.lock()
		server.requests++
		server.request_path = request[1]
		server.mutex.unlock()
		smoke_reply(mut connection, 200, 'text/event-stream', if server.claude {
			claude_response
		} else {
			codex_response
		}, false)!
	} else if server.claude && request[0] in ['GET', 'HEAD'] && request[1] == '/api/hello' {
		smoke_reply(mut connection, 200, 'application/json', '{"message":"hello"}', request[0] == 'HEAD')!
	} else {
		smoke_reply(mut connection, 404, 'text/plain', 'Not Found\n', request[0] == 'HEAD')!
	}
}

fn smoke_serve(mut listener net.TcpListener, mut server SmokeServer) {
	listener.set_accept_timeout(100 * time.millisecond)
	for !server.finished() {
		mut connection := listener.accept() or {
			if err.code() == net.err_timed_out_code { continue }
			server.mutex.lock()
			server.failure = err.msg()
			server.mutex.unlock()
			return
		}
		smoke_request(mut connection, mut server) or {
			server.mutex.lock()
			server.failure = err.msg()
			server.mutex.unlock()
		}
		connection.close() or {}
	}
}

struct SmokeChecks {
mut:
	failures []string
}

fn (mut checks SmokeChecks) check(condition bool, description string, detail string) {
	println('${description:-40} ' + if condition { 'ok' } else { 'FAIL' })
	flush_stdout()
	if !condition {
		checks.failures << description
		if detail != '' {
			println('  ' + detail.replace('\n', '\n  '))
			flush_stdout()
		}
	}
}

fn smoke_command(argv []string) sourcecommand.Output {
	return sourcecommand.capture_full(argv, os.environ(), -1, 16 * 1024 * 1024, cachecli.cancelled) or { sourcecommand.Output{ status: 127, stderr: err.msg() } }
}

pub fn run_cli_smoke(claude bool, executable string, timeout f64, work string, rg_path string, zsh_path string) !int {
	mut checks := SmokeChecks{}
	version := smoke_command([executable, '--version'])
	checks.check(version.status == 0 && if claude {
		version.stdout.contains('Claude Code')
	} else {
		version.stdout.starts_with('codex-cli ')
	}, if claude { 'Claude Code CLI starts' } else { 'Codex CLI starts' }, version.stdout + version.stderr)
	if version.stdout != '' {
		println('  [info] ' + version.stdout.trim_space())
		flush_stdout()
	}
	help := smoke_command([executable, '--help'])
	checks.check(help.status == 0 && help.stdout.contains(if claude {
		'--print'
	} else {
		'Run Codex non-interactively'
	}), if claude { 'Claude Code help is available' } else { 'Codex help is available' }, help.stdout + help.stderr)
	rg := smoke_command([rg_path, '--version'])
	checks.check(rg.status == 0 && rg.stdout.contains('ripgrep'), if claude {
		'system musl ripgrep starts'
	} else {
		'bundled musl ripgrep starts'
	}, rg.stdout + rg.stderr)
	if !claude {
		zsh := smoke_command([zsh_path, '--version'])
		checks.check(zsh.status == 0 && zsh.stdout.contains('zsh'), 'bundled musl zsh starts', zsh.stdout + zsh.stderr)
	}
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	port := listener.addr()!.port()!
	private := work + '/client-home'
	remove(private)!
	mkdir(private)!
	defer { remove(private) or {} }
	mut environment := os.environ()
	mut command := []string{}
	if claude {
		environment['HOME'] = private
		environment['ANTHROPIC_API_KEY'] = 'vinix-loopback-key'
		environment['ANTHROPIC_BASE_URL'] = 'http://127.0.0.1:${port}'
		environment['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'
		environment['DISABLE_AUTOUPDATER'] = '1'
		command = [executable, '--print', '--bare', '--debug', '--model', 'claude-sonnet-4-5',
			'--max-turns', '1', '--no-session-persistence',
			'Reply with the requested smoke-test phrase.']
	} else {
		environment['CODEX_HOME'] = private
		environment['OPENAI_API_KEY'] = 'vinix-loopback-key'
		provider := 'model_providers.vinix={name="Vinix loopback",base_url="http://127.0.0.1:${port}/v1",env_key="OPENAI_API_KEY",wire_api="responses",request_max_retries=0,stream_max_retries=0}'
		command = [executable, 'exec', '--skip-git-repo-check',
			'--dangerously-bypass-approvals-and-sandbox', '--ephemeral', '-C', '/tmp', '-m', 'gpt-5.1',
			'-c', provider, '-c', 'model_provider="vinix"',
			'Reply with the requested smoke-test phrase.']
	}
	mut server := &SmokeServer{ claude: claude, deadline: time.sys_mono_now() + u64(timeout * f64(time.second)) }
	previous := active_smoke
	active_smoke = server
	defer { active_smoke = previous }
	// SDK posix_spawn is safe with the active server thread. The thread never
	// observes or signals a PID; only the process owner cancels and reaps it.
	task := spawn smoke_serve(mut listener, mut server)
	mut problem := ''
	result := if claude {
		sourcecommand.capture_full(command, environment, timeout, 64 * 1024 * 1024, smoke_cancelled) or {
			problem = err.msg()
			sourcecommand.Output{ status: 1 }
		}
	} else {
		sourcecommand.run_owned(command, environment, smoke_cancelled, unsafe { nil }, unsafe { nil }) or {
			problem = err.msg()
			sourcecommand.Output{ status: 1 }
		}
	}
	server.stop()
	task.wait()
	mut debug := ''
	mut debug_files := []string{}
	for path in files(private + '/.claude/debug')! {
		if os.is_file(path) && path.ends_with('.txt') { debug_files << path }
	}
	if debug_files.len > 0 {
		debug_files.sort(a < b)
		mut latest := debug_files[0]
		for path in debug_files {
			if os.stat(path)!.mtime > os.stat(latest)!.mtime { latest = path }
		}
		debug = os.read_file(latest) or { '' }
	}
	if claude && result.stdout != '' {
		println(result.stdout.trim_right('\r\n'))
		flush_stdout()
	}
	passed := result.status == 0 && server.requests > 0 && (!claude || (server.request_path.starts_with('/v1/messages') && result.stdout.contains('VINIX CLAUDE LOOPBACK PASS')))
	details := if claude {
		'${problem}\nclaude exit status ${result.status}, request path ${server.request_path}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}\ndebug:\n${debug}\nserver:\n${server.failure}'
	} else {
		problem + if server.requests == 0 {
			'\ncodex did not reach the loopback server within 90 seconds'
		} else {
			'\ncodex exit status ${result.status}'
		}
	}
	checks.check(passed, if claude {
		'claude print completes a model turn'
	} else {
		'codex exec completes a model turn'
	}, details)
	println((if claude { 'CLAUDE' } else { 'CODEX' }) + ' SMOKE ' + if checks.failures.len > 0 {
		'FAIL'
	} else {
		'PASS'
	} + ' (${checks.failures.len} failures)')
	flush_stdout()
	if checks.failures.len > 0 {
		println('failed: ' + checks.failures.join(', '))
		flush_stdout()
		return 1
	}
	return 0
}

pub fn smoke_cli(root string, argv []string, claude bool) !int {
	args := cachecli.arguments(argv, ['--executable', '--work', '--timeout', '--rg', '--zsh'], [], [], 0, 0, 'Check the installed CLI against a local event-stream server.\nUsage: smoke [--executable PATH --work DIR --timeout 90 --rg PATH --zsh PATH]') or { return error_with_code(err.msg(), 2) }
	timeout := strconv.atof64(args.value('--timeout', '90')) or { return error_with_code(err.msg(), 2) }
	if math.is_nan(timeout) || math.is_inf(timeout, 0) || timeout <= 0 || timeout > 3600 {
		return error_with_code('--timeout must be positive and at most 3600', 2)
	}
	work := args.value('--work', os.temp_dir() + '/vinix-cli-smoke-' + os.getpid().str())
	mkdir(work)!
	defer { if '--work' !in args.options { remove(work) or {} } }
	return run_cli_smoke(claude, args.value('--executable', if claude { 'claude' } else { 'codex' }), timeout, work, args.value('--rg', if claude {
		'rg'
	} else {
		'/usr/lib/codex/codex-path/rg'
	}), args.value('--zsh', '/usr/lib/codex/codex-resources/zsh/bin/zsh'))!
}
