// SPDX-License-Identifier: GPL-2.0-or-later
module minecraftnative

import json2
import os
import strconv
import time

pub struct AuthEndpoints {
pub:
	device       string = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode'
	token        string = 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token'
	xbl          string = 'https://user.auth.xboxlive.com/user/authenticate'
	xsts         string = 'https://xsts.auth.xboxlive.com/xsts/authorize'
	minecraft    string = 'https://api.minecraftservices.com/authentication/login_with_xbox'
	entitlements string = 'https://api.minecraftservices.com/entitlements/mcstore'
	profile      string = 'https://api.minecraftservices.com/minecraft/profile'
}

pub struct AuthRequest {
pub:
	url     string
	method  string
	body    string
	headers map[string]string
}

pub struct AuthResponse {
pub:
	status int
	data   json2.Any
}

pub struct LoginService {
pub:
	endpoints AuthEndpoints
	request   fn (AuthRequest) !AuthResponse = auth_request
	now       fn () f64                      = auth_now
	sleep     fn (int) !                     = auth_sleep
}

pub struct Account {
pub:
	name  string
	uuid  string
	token string
	xuid  string
}

fn auth_now() f64 { return f64(time.now().unix_milli()) / 1000 }

fn auth_sleep(seconds int) ! {
	if seconds < 0 { return error('Invalid negative Microsoft polling interval') }
	deadline := time.sys_mono_now() + u64(seconds) * u64(time.second)
	for {
		command_checkpoint()!
		now := time.sys_mono_now()
		if now >= deadline { break }
		remaining := deadline - now
		time.sleep(time.Duration(if remaining < u64(50 * time.millisecond) {
			remaining
		} else {
			u64(50 * time.millisecond)
		}))
	}
	command_checkpoint()!
}

pub fn form_encode(fields [][]string) !string {
	mut pairs := []string{}
	for pair in fields {
		if pair.len != 2 { return error('Invalid OAuth form field') }
		mut values := []string{}
		for value in pair {
			mut encoded := ''
			for byte in value.bytes() {
				if byte.is_alnum() || byte in [u8(`-`), `.`, `_`, `~`] {
					encoded += byte.ascii_str()
				} else if byte == ` ` {
					encoded += '+'
				} else {
					encoded += '%' + byte.hex().to_upper()
				}
			}
			values << encoded
		}
		pairs << values.join('=')
	}
	return pairs.join('&')
}

fn private_text(path string, content string) ! {
	os.write_file(path, content)!
	os.chmod(path, 0o600)!
}

// Secrets are stored inside a private 0700 workspace, never in curl's argv.
// curl supplies HTTP/TLS; V owns request construction, responses and cleanup.
pub fn auth_request(request AuthRequest) !AuthResponse {
	work := temporary(os.temp_dir(), 'vinix-minecraft-auth-')!
	defer { retire(work) }
	mut headers := []string{}
	for name, value in request.headers {
		if name.contains_any('\r\n\x00') || value.contains_any('\r\n\x00') {
			return error('Invalid authentication header')
		}
		headers << name + ': ' + value
	}
	private_text(work + '/headers', headers.join('\n') + '\n')!
	mut argv := ['curl', '-sS', '--max-time', '60', '--request', request.method, '--header',
		'@' + work + '/headers', '--output', work + '/response', '--write-out', '%{http_code}']
	if request.method == 'POST' {
		private_text(work + '/request', request.body)!
		argv << ['--data-binary', '@' + work + '/request']
	}
	argv << ['--', request.url]
	command(argv, work + '/status')!
	status := strconv.atoi(os.read_file(work + '/status')!.trim_space())!
	if status < 100 || status > 599 { return error('Invalid authentication HTTP status') }
	if os.file_size(work + '/response') > 10 * 1024 * 1024 {
		return error('Authentication response exceeds 10 MiB')
	}
	data := json2.decode[json2.Any](os.read_file(work + '/response')!) or {
		return error('Invalid authentication JSON response from ' + request.url + ': ' + err.msg())
	}
	return AuthResponse{status, data}
}

fn (service LoginService) form(url string, fields [][]string) !AuthResponse {
	return service.request(AuthRequest{url, 'POST', form_encode(fields)!, {
		'Content-Type': 'application/x-www-form-urlencoded'
	}})!
}

fn (service LoginService) json(url string, value json2.Any) !AuthResponse {
	return service.request(AuthRequest{url, 'POST', json2.encode(value), {
		'Content-Type': 'application/json'
		'Accept':       'application/json'
	}})!
}

fn accepted(response AuthResponse) !json2.Any {
	if response.status >= 400 { return error('minecraft-login: HTTP ' + response.status.str()) }
	return response.data
}

fn (service LoginService) get(url string, token string) !json2.Any {
	return accepted(service.request(AuthRequest{url, 'GET', '', {
		'Authorization': 'Bearer ' + token
	}})!)!
}

pub fn (service LoginService) microsoft_token(client_id string) !string {
	start := service.form(service.endpoints.device, [['client_id', client_id],
		['scope', 'XboxLive.signin offline_access']])!
	if start.status >= 400 {
		return error('minecraft-login: Microsoft rejected the application id: ' + optional(start.data,
			'error_description', start.data).str())
	}
	println('\n  Open ' + text(field(start.data, 'verification_uri')!)! + ' and enter the code ' +
		text(field(start.data, 'user_code')!)!)
	println('  Waiting for approval…')
	mut interval := optional(start.data, 'interval', json2.Any(5)).int()
	deadline := service.now() + f64(optional(start.data, 'expires_in', json2.Any(900)).int())
	for service.now() < deadline {
		service.sleep(interval)!
		response := service.form(service.endpoints.token, [['client_id', client_id],
			['grant_type', 'urn:ietf:params:oauth:grant-type:device_code'],
			['device_code', text(field(start.data, 'device_code')!)!]])!
		if response.status < 400 { return text(field(response.data, 'access_token')!)! }
		problem := optional(response.data, 'error', json2.Any(json2.Null{})).str()
		if problem == 'authorization_pending' { continue }
		if problem == 'slow_down' {
			interval += 5
			continue
		}
		return error('minecraft-login: sign-in failed: ' + optional(response.data,
			'error_description', json2.Any(problem)).str())
	}
	return error('minecraft-login: the code expired before it was approved')
}

pub fn (service LoginService) minecraft_session(microsoft_access_token string) !Account {
	xbl := accepted(service.json(service.endpoints.xbl, json2.Any({
		'Properties':   json2.Any({
			'AuthMethod': json2.Any('RPS')
			'SiteName':   json2.Any('user.auth.xboxlive.com')
			'RpsTicket':  json2.Any('d=' + microsoft_access_token)
		})
		'RelyingParty': json2.Any('http://auth.xboxlive.com')
		'TokenType':    json2.Any('JWT')
	}))!)!
	xsts_response := service.json(service.endpoints.xsts, json2.Any({
		'Properties':   json2.Any({
			'SandboxId':  json2.Any('RETAIL')
			'UserTokens': json2.Any([field(xbl, 'Token')!])
		})
		'RelyingParty': json2.Any('rp://api.minecraftservices.com/')
		'TokenType':    json2.Any('JWT')
	}))!
	if xsts_response.status == 401 {
		match optional(xsts_response.data, 'XErr', json2.Any(0)).i64() {
			2148916233 {
				return error('minecraft-login: this Microsoft account has no Xbox profile')
			}
			2148916238 {
				return error('minecraft-login: this is a child account and needs to join a family')
			}
			else {}
		}
	}
	xsts := accepted(xsts_response)!
	claims := items(field(field(xsts, 'DisplayClaims')!, 'xui')!)!
	if claims.len == 0 { return error('Missing Xbox user claims') }
	user_hash := text(field(claims[0], 'uhs')!)!
	xuid := optional(claims[0], 'xid', json2.Any('0')).str()
	session := accepted(service.json(service.endpoints.minecraft, json2.Any({
		'identityToken': json2.Any('XBL3.0 x=' + user_hash + ';' + text(field(xsts, 'Token')!)!)
	}))!)!
	token := text(field(session, 'access_token')!)!
	entitlements := service.get(service.endpoints.entitlements, token)!
	if items(optional(entitlements, 'items', json2.Any([]json2.Any{})))!.len == 0 {
		return error("minecraft-login: this account does not own Minecraft: Java Edition. Run 'minecraft --demo' to play Mojang's free demo instead.")
	}
	profile := service.get(service.endpoints.profile, token)!
	return Account{text(field(profile, 'name')!)!, text(field(profile, 'id')!)!, token, xuid}
}

pub fn save_session(path string, account Account) ! {
	work := temporary(os.dir(path), '.minecraft-session-')!
	defer { retire(work) }
	private_text(work + '/session', [
		'# Written by minecraft-login. Contains a Minecraft session token.',
		'MC_PLAYER_NAME=' + shell_quote(account.name),
		'MC_PLAYER_UUID=' + shell_quote(account.uuid),
		'MC_PLAYER_XUID=' + shell_quote(account.xuid),
		'MC_ACCESS_TOKEN=' + shell_quote(account.token),
	].join('\n') + '\n')!
	command_checkpoint()!
	os.mv(work + '/session', path)!
}

pub fn login_cli(args []string) int {
	guard := own_commands()
	defer { guard.close() }
	login_stage(args) or {
		eprintln(err)
		return if interrupt_status() != 0 {
			interrupt_status()
		} else if err is ArgumentError {
			2
		} else {
			1
		}
	}
	return 0
}

fn login_stage(args []string) ! {
	mut values := map[string]string{}
	names := ['--session', '--client-id', '--help']
	mut index := 0
	for index < args.len {
		arg := args[index]
		name := arg.all_before('=')
		matches := names.filter(it == name || (name.starts_with('--') && it.starts_with(name)))
		if arg == '-h' || matches == ['--help'] {
			if arg.contains('=') { return ArgumentError{'--help does not take a value'} }
			println('Usage: minecraft-login --session PATH [--client-id APPLICATION_ID]\nSet VINIX_MINECRAFT_MSA_CLIENT_ID to an application approved for Minecraft sign-in.')
			return
		}
		if matches.len != 1 { return ArgumentError{'unknown or ambiguous option: ' + arg} }
		key := matches[0]
		if arg.contains('=') {
			values[key] = arg.all_after('=')
		} else {
			index++
			if index >= args.len || args[index].starts_with('--') {
				return ArgumentError{'missing value for ' + key}
			}
			values[key] = args[index]
		}
		index++
	}
	if '--session' !in values { return ArgumentError{'--session is required'} }
	client_id := values['--client-id'] or { os.getenv('VINIX_MINECRAFT_MSA_CLIENT_ID') }
	if client_id == '' {
		return error("minecraft-login: no Microsoft application id configured.\n  Register an Azure application approved for Minecraft sign-in and set\n  VINIX_MINECRAFT_MSA_CLIENT_ID to its application id.\n  Mojang's free demo needs no account: run 'minecraft --demo'.")
	}
	service := LoginService{}
	account := service.minecraft_session(service.microsoft_token(client_id)!)!
	save_session(values['--session'], account)!
	println('minecraft-login: signed in as ' + account.name)
}
