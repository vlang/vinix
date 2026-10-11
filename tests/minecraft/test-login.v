// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import bundlehost as bh
import json2
import minecraftnative as mc
import os
import net
import time

struct Flow {
mut:
	mode     string
	now      f64
	polls    int
	requests []mc.AuthRequest
	sleeps   []int
}

__global flow Flow

fn parsed(data string) !json2.Any { return json2.decode[json2.Any](data)! }

fn clock() f64 { return flow.now }

fn sleep(seconds int) ! {
	flow.sleeps << seconds
	flow.now += f64(seconds)
}

fn request(req mc.AuthRequest) !mc.AuthResponse {
	flow.requests << req
	mut status := 200
	mut body := ''
	match req.url {
		'device' {
			assert req.method == 'POST' && req.body == 'client_id=id%2Bwith+space&scope=XboxLive.signin+offline_access'
			assert req.headers['Content-Type'] == 'application/x-www-form-urlencoded'
			body = '{"verification_uri":"https://example.invalid/approve","user_code":"TEST-CODE","device_code":"private-code","interval":2,"expires_in":20}'
			if flow.mode == 'rejected' {
				status = 400
				body = '{"error_description":"bad application"}'
			}
			if flow.mode == 'expired' { body = body.replace('expires_in":20', 'expires_in":4') }
			if flow.mode == 'default' {
				body = '{"verification_uri":"https://example.invalid/approve","user_code":"TEST-CODE","device_code":"private-code"}'
			}
		}
		'token' {
			assert req.body == 'client_id=id%2Bwith+space&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code&device_code=private-code'
			flow.polls++
			if flow.mode in ['expired', 'pending'] || (flow.mode == 'slow' && flow.polls == 1) {
				status = 400
				body = '{"error":"authorization_pending"}'
			} else if flow.mode == 'slow' && flow.polls == 2 {
				status = 400
				body = '{"error":"slow_down"}'
			} else if flow.mode == 'denied' {
				status = 400
				body = '{"error":"access_denied","error_description":"approval denied"}'
			} else {
				body = '{"access_token":"microsoft-secret"}'
			}
		}
		'xbl' {
			payload := parsed(req.body)!
			assert req.headers['Accept'] == 'application/json'
			assert mc.field(mc.field(payload, 'Properties')!, 'RpsTicket')!.str() == 'd=microsoft-secret'
			assert mc.field(payload, 'RelyingParty')!.str() == 'http://auth.xboxlive.com'
			body = '{"Token":"xbl-secret"}'
			if flow.mode == 'xbl-http' {
				status = 500
				body = '{}'
			}
		}
		'xsts' {
			payload := parsed(req.body)!
			assert mc.items(mc.field(mc.field(payload, 'Properties')!, 'UserTokens')!)!.map(it.str()) == ['xbl-secret']
			assert mc.field(payload, 'RelyingParty')!.str() == 'rp://api.minecraftservices.com/'
			body = '{"Token":"xsts-secret","DisplayClaims":{"xui":[{"uhs":"user-hash","xid":"12345"}]}}'
			if flow.mode == 'no-xuid' {
				body = '{"Token":"xsts-secret","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}'
			}
			if flow.mode == 'no-xbox' {
				status = 401
				body = '{"XErr":2148916233}'
			}
			if flow.mode == 'child' {
				status = 401
				body = '{"XErr":2148916238}'
			}
			if flow.mode == 'xsts-http' {
				status = 403
				body = '{}'
			}
			if flow.mode == 'no-claims' {
				body = '{"Token":"xsts-secret","DisplayClaims":{"xui":[]}}'
			}
		}
		'minecraft' {
			assert mc.field(parsed(req.body)!, 'identityToken')!.str() == 'XBL3.0 x=user-hash;xsts-secret'
			body = '{"access_token":"minecraft-secret"}'
		}
		'entitlements' {
			assert req.method == 'GET' && req.headers['Authorization'] == 'Bearer minecraft-secret'
			body = if flow.mode == 'unowned' {
				'{"items":[]}'
			} else {
				'{"items":[{"name":"game_minecraft"}]}'
			}
		}
		'profile' {
			assert req.method == 'GET' && req.headers['Authorization'] == 'Bearer minecraft-secret'
			body = '{"name":"Steve","id":"0123456789abcdef0123456789abcdef"}'
		}
		else { return error('Unexpected request ' + req.url) }
	}
	return mc.AuthResponse{status, parsed(body)!}
}

fn service() mc.LoginService {
	return mc.LoginService{ endpoints: mc.AuthEndpoints{ device: 'device', token: 'token', xbl: 'xbl', xsts: 'xsts', minecraft: 'minecraft', entitlements: 'entitlements', profile: 'profile' }, request: request, now: clock, sleep: sleep }
}

fn checked(work string) ! {
	assert mc.form_encode([['special +&=/\n', '世界\x01~']])! == 'special+%2B%26%3D%2F%0A=%E4%B8%96%E7%95%8C%01~'
	for mode in ['approved', 'slow', 'default', 'no-xuid'] {
		flow = Flow{ mode: mode }
		api := service()
		token := api.microsoft_token('id+with space')!
		assert token == 'microsoft-secret'
		if mode == 'slow' {
			assert flow.sleeps == [2, 2, 7]
		}
		if mode == 'default' {
			assert flow.sleeps == [5]
		}
		account := api.minecraft_session(token)!
		assert account.name == 'Steve' && account.uuid == '0123456789abcdef0123456789abcdef' && account.token == 'minecraft-secret'
		assert account.xuid == if mode == 'no-xuid' { '0' } else { '12345' }
		assert flow.requests.map(it.url).filter(it !in ['token']) == ['device', 'xbl', 'xsts',
			'minecraft', 'entitlements', 'profile']
	}
	for row in [['rejected', 'bad application'], ['denied', 'approval denied'],
		['expired', 'code expired']] {
		flow = Flow{ mode: row[0] }
		mut failed := false
		service().microsoft_token('id+with space') or {
			assert err.msg().contains(row[1])
			failed = true
		}
		assert failed
	}
	for row in [['no-xbox', 'no Xbox profile'], ['child', 'child account'], ['xbl-http', 'HTTP 500'],
		['xsts-http', 'HTTP 403'], ['no-claims', 'Missing Xbox user claims'],
		['unowned', 'does not own Minecraft']] {
		flow = Flow{ mode: row[0] }
		mut failed := false
		service().minecraft_session('microsoft-secret') or {
			assert err.msg().contains(row[1])
			failed = true
		}
		assert failed
		assert flow.requests.all(it.url != 'profile')
	}
	path := work + '/session/account.env'
	mc.save_session(path, mc.Account{"Steve'quoted", 'uuid', 'token-secret', 'xuid'})!
	assert os.read_file(path)!.contains("MC_PLAYER_NAME='Steve'\\''quoted'")
	assert os.stat(path)!.mode & 0o777 == 0o600
	result := os.exec(['/bin/sh', '-c',
		'. "$1"; printf "%s|%s|%s|%s" "$MC_PLAYER_NAME" "$MC_PLAYER_UUID" "$MC_PLAYER_XUID" "$MC_ACCESS_TOKEN"',
		'session', path])
	assert result.exit_code == 0 && result.output == "Steve'quoted|uuid|xuid|token-secret"
	assert os.walk_ext(work, '').all(!it.contains('.minecraft-session-'))
	println('PASS ordered OAuth polling, slowdown/default/expiry/denial, Xbox exchange/errors, entitlement gate and private shell-sourceable session')
}

fn serve(mut listener net.TcpListener) ! {
	for _ in 0 .. 7 {
		mut connection := listener.accept()!
		connection.set_read_timeout(5 * time.second)
		mut input := ''
		mut buffer := []u8{len: 1024}
		for !input.contains('\r\n\r\n') {
			n := connection.read(mut buffer)!
			if n == 0 { return error('Incomplete authentication request') }
			input += buffer[..n].bytestr()
		}
		header := input.all_before('\r\n\r\n')
		mut body := input.all_after('\r\n\r\n')
		mut headers := map[string]string{}
		mut size := 0
		for line in header.split('\r\n')[1..] {
			key, value := line.all_before(':'), line.all_after(':').trim_space()
			headers[key] = value
			if key.to_lower() == 'content-length' { size = value.int() }
		}
		if size > 1024 * 1024 { return error('Oversized authentication request') }
		for body.len < size {
			n := connection.read(mut buffer)!
			if n == 0 { return error('Incomplete authentication body') }
			body += buffer[..n].bytestr()
		}
		first := header.split('\r\n')[0].fields()
		response := request(mc.AuthRequest{first[1].trim_left('/'), first[0], body, headers})!
		json := json2.encode(response.data)
		connection.write_string('HTTP/1.1 ' + response.status.str() + ' Fixture\r\nContent-Type: application/json\r\nContent-Length: ' + json.len.str() + '\r\nConnection: close\r\n\r\n' + json)!
		connection.close()!
	}
}

fn actual_http() ! {
	// This observer is local even when the caller routes production HTTP
	// through a proxy. Restore both curl spellings after the fixture.
	mut previous := map[string]string{}
	mut absent := []string{}
	for name in ['NO_PROXY', 'no_proxy'] {
		if value := os.getenv_opt(name) {
			previous[name] = value
		} else {
			absent << name
		}
		os.setenv(name, '127.0.0.1', true)
	}
	defer {
		for name, value in previous { os.setenv(name, value, true) }
		for name in absent { os.unsetenv(name) }
	}
	flow = Flow{ mode: 'approved' }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	defer { listener.close() or {} }
	base := 'http://127.0.0.1:' + listener.addr()!.port()!.str()
	observer := spawn serve(mut listener)
	api := mc.LoginService{ endpoints: mc.AuthEndpoints{ device: base + '/device', token: base + '/token', xbl: base + '/xbl', xsts: base + '/xsts', minecraft: base + '/minecraft', entitlements: base + '/entitlements', profile: base + '/profile' }, now: clock, sleep: sleep }
	account := api.minecraft_session(api.microsoft_token('id+with space')!)!
	observer.wait()!
	assert account.name == 'Steve' && account.token == 'minecraft-secret'
	println('PASS real curl device-code/form/JSON/Bearer exchanges against an independent local HTTP observer')
}

fn main() {
	work := bh.temporary(os.temp_dir(), 'vinix-minecraft-login-tests-') or { panic(err) }
	defer { bh.retire(work) }
	checked(work) or { panic(err) }
	actual_http() or { panic(err) }
	println('MINECRAFT LOGIN NATIVE PASS')
}
