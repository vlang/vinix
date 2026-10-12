// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import net.http
import os
import time
import guestvalidation

fn mock_client() !bool {
	name := os.executable().all_after_last('/')
	if name !in ['mock-codex', 'mock-claude', 'mock-rg', 'mock-zsh'] { return false }
	if os.args[1..] == ['--version'] {
		println(match name {
			'mock-codex' { 'codex-cli fixture' }
			'mock-claude' { 'fixture Claude Code' }
			'mock-rg' { 'ripgrep fixture' }
			else { 'zsh fixture' }
		})
		return true
	}
	if os.args[1..] == ['--help'] {
		println(if name == 'mock-claude' { '--print' } else { 'Run Codex non-interactively' })
		return true
	}
	work := os.getenv('VINIX_MOCK_SMOKE_WORK')
	mode := os.getenv('VINIX_MOCK_SMOKE_MODE')
	os.write_file(work + '/client.pid', os.getpid().str())!
	claude := name == 'mock-claude'
	if mode == 'timeout' {
		for { time.sleep(10 * time.millisecond) }
	}
	if mode == 'early-exit' { exit(7) }
	mut url := ''
	if claude {
		assert os.args[1..] == ['--print', '--bare', '--debug', '--model', 'claude-sonnet-4-5',
			'--max-turns', '1', '--no-session-persistence',
			'Reply with the requested smoke-test phrase.']
		assert os.getenv('ANTHROPIC_API_KEY') == 'vinix-loopback-key' && os.getenv('DISABLE_AUTOUPDATER') == '1'
		url = os.getenv('ANTHROPIC_BASE_URL')
		hello := http.fetch(method: .head, url: url + '/api/hello')!
		assert hello.status_code == 200 && hello.body == ''
		assert http.get(url + '/api/hello')!.body == '{"message":"hello"}'
		url += if mode == 'wrong-path' { '/other' } else { '/v1/messages?fixture=1' }
	} else {
		assert os.args[1..11] == ['exec', '--skip-git-repo-check',
			'--dangerously-bypass-approvals-and-sandbox', '--ephemeral', '-C', '/tmp', '-m', 'gpt-5.1',
			'-c', os.args[10]]
		assert os.getenv('OPENAI_API_KEY') == 'vinix-loopback-key'
		url = os.args[10].all_after('base_url="').all_before('"') + '/responses'
	}
	reply := http.fetch(method: .post, url: url, data: '{"stream":true}')!
	assert reply.status_code == 200 && reply.body == if claude {
		guestvalidation.claude_response
	} else {
		guestvalidation.codex_response
	}
	if mode == 'status' { exit(7) }
	if mode != 'phrase' {
		println(if claude { 'VINIX CLAUDE LOOPBACK PASS' } else { 'VINIX CODEX LOOPBACK PASS' })
		flush_stdout()
	}
	// This diagnostic exceeds the ordinary command helper's old prefix bound.
	mut errors := os.stderr()
	text := 'mock diagnostic\n'.repeat(6000)
	unsafe { errors.write_full_buffer(text.str, usize(text.len))! }
	return true
}

fn frozen_body(source string) !string {
	data := source.all_after('response_body = (').all_before(').encode()')
	mut position := 0
	mut result := []u8{}
	for position < data.len {
		if data[position] !in [u8(`'`), `"`] {
			position++
			continue
		}
		quote := data[position]
		position++
		for position < data.len && data[position] != quote {
			byte := data[position]
			position++
			if byte != `\\` {
				result << byte
				continue
			}
			if position == data.len { return error('incomplete frozen literal') }
			escaped := data[position]
			position++
			result << match escaped {
				`n` { u8(`\n`) }
				`r` { u8(`\r`) }
				`t` { u8(`\t`) }
				`\\`, `'`, `"` { escaped }
				else { return error('unsupported frozen literal escape') }
			}
		}
		position++
	}
	return result.bytestr()
}

fn cases(work string) ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	for claude in [false, true] {
		original := os.exec(['git', '-C', root, 'show',
			'71d666c4:tests/' + if claude { 'claude' } else { 'codex' } + '/smoke.py'])
		assert original.exit_code == 0
		assert frozen_body(original.output)! == if claude {
			guestvalidation.claude_response
		} else {
			guestvalidation.codex_response
		}
	}
	for name in ['mock-codex', 'mock-claude', 'mock-rg', 'mock-zsh'] {
		os.cp(os.executable(), work + '/' + name)!
		os.chmod(work + '/' + name, 0o755)!
	}
	before := os.ls('/dev/fd')!.len
	for claude in [false, true] {
		modes := if claude {
			['complete', 'wrong-path', 'phrase', 'status', 'early-exit', 'timeout']
		} else {
			['complete', 'status', 'early-exit', 'timeout']
		}
		for mode in modes {
			directory := work + '/' + if claude { 'claude-' + mode } else { 'codex-' + mode }
			gamehost.mkdir(directory)!
			os.setenv('VINIX_MOCK_SMOKE_WORK', directory, true)
			os.setenv('VINIX_MOCK_SMOKE_MODE', mode, true)
			status := guestvalidation.run_cli_smoke(claude, work + '/' + if claude {
				'mock-claude'
			} else {
				'mock-codex'
			}, if mode == 'timeout' { 1 } else { 10 }, directory, work + '/mock-rg', work + '/mock-zsh')!
			assert status == if mode == 'complete' { 0 } else { 1 }
			pid := os.read_file(directory + '/client.pid')!.int()
			assert C.kill(pid, 0) != 0 && C.errno == C.ESRCH
			assert !os.exists(directory + '/client-home')
		}
	}
	os.unsetenv('VINIX_MOCK_SMOKE_WORK')
	os.unsetenv('VINIX_MOCK_SMOKE_MODE')
	assert os.ls('/dev/fd')!.len == before
}

fn main() {
	if mock_client() or {
		eprintln(err)
		exit(1)
	} {
		return
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	cases(work) or {
		eprintln(err)
		exit(1)
	}
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	println('NATIVE CLI SMOKE / exact frozen SSE bytes, original argv/environment, complete model exchange and HEAD/GET, wrong path/phrase/status/early exit/timeouts, home/PID/FD cleanup: PASS')
}
