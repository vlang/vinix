// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import net
import os
import time

struct BrowserResult {
	name string
	executable string
	page_sha256 string
	javascript_callback string
	dom_verified bool
	screenshot_sha256 string
}

struct BrowserHttpResult {
	callback string
	error string
}

fn browser_executable(name string) !string {
	paths := if name == 'chromium' { ['/usr/lib/chromium/chrome', '/usr/lib/chromium/chromium'] }
		else { ['/usr/lib/firefox-esr/firefox-esr', '/usr/lib/firefox/firefox'] }
	for path in paths {
		if !os.is_executable(path) { continue }
		bytes := os.read_bytes(path)!
		if bytes.len >= 4 && bytes[..4] == [u8(127), `E`, `L`, `F`] { return path }
	}
	return error('unsupported: browser ELF binary is missing: ' + name)
}

fn browser_http(mut listener net.TcpListener, page string, verdict string, stop chan bool) BrowserHttpResult {
	mut callback := ''
	for {
		select { _ := <-stop { return BrowserHttpResult{callback: callback} } else {} }
		mut connection := listener.accept() or { continue }
		connection.set_read_timeout(time.second)
		connection.set_write_timeout(time.second)
		mut request := ''
		mut buffer := [1024]u8{}
		for request.len < 16384 && !request.contains('\r\n\r\n') {
			n := connection.read(mut buffer) or { break }
			if n <= 0 { break }
			request += buffer[..n].bytestr()
		}
		line := request.all_before('\r\n')
		mut body := ''
		mut mime := 'text/html; charset=utf-8'
		mut status := '404 Not Found'
		if line == 'GET / HTTP/1.1' || line == 'GET / HTTP/1.0' {
			body = page
			status = '200 OK'
		} else if line == 'GET ' + verdict + ' HTTP/1.1' || line == 'GET ' + verdict + ' HTTP/1.0' {
			callback = line
			body = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'
			mime = 'image/svg+xml'
			status = '200 OK'
		}
		reply := 'HTTP/1.1 ' + status + '\r\nContent-Type: ' + mime
			+ '\r\nContent-Length: ' + body.len.str() + '\r\nConnection: close\r\n\r\n' + body
		mut sent := 0
		for sent < reply.len {
			n := connection.write_string(reply[sent..]) or {
				connection.close() or {}
				return BrowserHttpResult{callback, err.msg()}
			}
			if n <= 0 { connection.close() or {}; return BrowserHttpResult{callback, 'short browser HTTP reply'} }
			sent += n
		}
		connection.close() or {}
	}
	return BrowserHttpResult{}
}

fn (mut suite Suite) browser(name string) ! {
	suite.package(if name == 'firefox' { 'firefox-esr' } else { name })!
	program := browser_executable(name)!
	// These tests invoke ELF engines directly. An inherited sandbox-disable
	// environment is a failing precondition, not a qualification fallback.
	for key, value in os.environ() {
		if key.starts_with('MOZ_DISABLE_') && key.ends_with('_SANDBOX') && value != '' && value != '0' {
			return error('browser qualification inherited disabled sandbox: ' + key)
		}
	}
	expect(C.getuid() != 0, 'browser qualification requires an ordinary user')!
	suite.execute(program, ['--version'])!
	profile := suite.work + '/' + name + '-profile'
	os.mkdir(profile)!
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	listener.set_accept_timeout(200 * time.millisecond)
	address := listener.addr()!.str()
	nonce := sha256.sum((suite.work + time.now().unix_nano().str()).bytes()).hex()
	verdict := '/result/' + nonce + '/42'
	page := '<!doctype html><meta charset="utf-8"><style>body{background:#fff}#verdict{color:#06c;font-size:48px}</style>'
		+ '<p id="verdict">pending</p><script>const answer=6*7;document.getElementById("verdict").textContent=answer;'
		+ 'const proof=new Image();proof.src="/result/' + nonce + '/"+answer;document.body.appendChild(proof);</script>'
	stop := chan bool{cap: 1}
	worker := spawn browser_http(mut listener, page, verdict, stop)
	mut finished := false
	defer { if !finished { stop <- true; _ = worker.wait() } }
	mut dom := ''
	mut screenshot := ''
	if name == 'chromium' {
		dom = suite.execute(program, ['--headless', '--user-data-dir=' + profile,
			'--timeout=30000', '--dump-dom', 'http://' + address + '/'])!
		expect(dom.contains('id="verdict">42</p>'), 'Chromium did not execute page JavaScript')!
	} else {
		png := suite.work + '/firefox.png'
		suite.execute(program, ['--headless', '--no-remote', '--profile', profile,
			'--window-size', '800,600', '--screenshot', png, 'http://' + address + '/'])!
		bytes := os.read_bytes(png)!
		expect(bytes.len > 256 && bytes[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10],
			'Firefox did not render a PNG')!
		screenshot = sha256.sum(bytes).hex()
	}
	stop <- true
	proof := worker.wait()
	finished = true
	expect(proof.error == '' && proof.callback.contains(verdict), 'browser did not publish the nonce-bearing JavaScript result')!
	suite.browsers << BrowserResult{name, program, sha256.sum(page.bytes()).hex(), proof.callback,
		name == 'chromium', screenshot}
}
