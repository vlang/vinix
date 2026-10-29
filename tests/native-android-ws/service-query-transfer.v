// SPDX-License-Identifier: GPL-2.0-or-later
// Credential-free fixture delivery to QEMU usernet; never a general file server.
module main

import crypto.sha256
import json2
import net
import os
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, uint) int
fn C.write(int, voidptr, uint) int
fn C.fstat(int, &C.stat) int

const runner_path = '/Users/alex/.local/state/vinix/android/service-query-run-arm64-r1'
const runner_pin = '8ef76b9e4c9f1eb0cc84780eaa0b618a3a70f317cd4f0e87824ddcdffcae8727'
const fixture_root = '/Users/alex/.local/state/vinix/android/service-query-fixture-2026-10-27-r1'
const client_pin = '890de9d4ff410aaf5cd87a52b630ccfa7280fd3c0b2b38eee57159d525b1565d'
const disabled_pin = 'e5075f571f3b8334dded40accb08257ccfdf83e8526a7b61e502d586daa66048'
const direct_boot_runner = '/Users/alex/.local/state/vinix/android/direct-boot-run-2026-10-27-r1/run'
const direct_boot_runner_pin = '8caab5559b73dbe1ffc9645006e899fd82dfbe5cfac810df4f189db9eb152a60'
const direct_boot_fixture = '/Users/alex/.local/state/vinix/android/direct-boot-fixture-2026-10-27-r1'
const direct_boot_client_pin = 'a77c25679d47032a8bac73a8ec7751dae271f7828973a8f9b722f004a0ad0c02'
const direct_boot_disabled_pin = '91e209b043a1f65379ecf16107263d513681bb56bbf25bbce11022d0824f9af5'
const credential_storage_runner = '/Users/alex/.local/state/vinix/android/credential-storage-run-2026-10-27-r1/run'
const credential_storage_runner_pin = '74cc1fb3721c400d4a64d5c7e0c9fb095b0404aa9eed927cbfb6ace06774cb46'
const credential_storage_fixture = '/Users/alex/.local/state/vinix/android/credential-storage-fixture-2026-10-27-r1'
const credential_storage_client_pin = '22bc2b0aa822b2305f8ed63b50be32114ca55d1d83f79ca468f8f6addc6e373e'
const credential_storage_disabled_pin = '42723f25adaf0a5ae789a37e4bddff512d10b219c187d368fce61de1f700f752'
const broadcast_result_runner = '/Users/alex/.local/state/vinix/android/broadcast-result-run-2026-10-27-r1/run'
const broadcast_result_runner_pin = '95be25cf1f8837bc717d200b0b92642c3085adbd789aad25356b89a73f07a8df'
const broadcast_result_fixture = '/Users/alex/.local/state/vinix/android/broadcast-result-fixture-2026-10-27-r1'
const broadcast_result_client_pin = '44f6c4356a5d031cf68191476bb0d2fb0fc2ceec8ecea26ffd395024d19321e7'
const broadcast_result_disabled_pin = '5293215a5899d2adb3ca9c6a52248c10874a2ad5b2e9cf08168935e829527966'
const onboarding_api_runner = '/Users/alex/.local/state/vinix/android/onboarding-api-run-2026-10-27-r1/run'
const onboarding_api_runner_pin = '0c8926b74244b7f505ffa6aafb6ff8a6e7beef2bd96369310a30d35d063b10b8'
const child_attach_apk = '/Users/alex/.local/state/vinix/android/child-attach-checks-2026-10-27-r1/apk/probe.apk'
const child_attach_apk_pin = '27869d74fd03598dda9b75b740cbaf2efcc423ee0c5ff3b2f447d22ade9f999e'
const settings_global_apk = '/Users/alex/.local/state/vinix/android/settings-global-checks-2026-10-27-r1/apk/probe.apk'
const settings_global_apk_pin = 'c3e912e4e05c2af28d6d64d1fcb46874136a6164f7e2e19cc5ba1b62d950fedd'
const application_restrictions_runner = '/Users/alex/.local/state/vinix/android/application-restrictions-run-2026-10-28-r2/run'
const application_restrictions_runner_pin = '1079d41f4df536e7a14c468e22a6e8021449dd2f36d563ed40e108f4e11abd53'
const application_restrictions_apk = '/Users/alex/.local/state/vinix/android/application-restrictions-fixture-2026-10-28-r2/probe.apk'
const application_restrictions_apk_pin = '1fcd38978709198743aa9127b14f02bbebbf55e1f4d7793cd03270f3c3c25a07'
const auth_exception_api_runner = '/Users/alex/.local/state/vinix/android/auth-exception-api-run-2026-10-29-r1/run'
const auth_exception_api_runner_pin = '49e53828402f44c5c45afb8dd611bbf6198b4046da19d37db2c6d0195c1fd0e1'
const authenticator_exception_apk = '/Users/alex/.local/state/vinix/android/authenticator-private-exception-check-2026-10-29-r1/fixture/probe.apk'
const authenticator_exception_apk_pin = 'c4e78b7c46d2d35f63d60bb8d45c3964ede94553f63e3cca9d0bebbcd261a941'
const maps_network_apk = '/Users/alex/.local/state/vinix/android/maps-network-fixture-2026-10-29-r1/probe.apk'
const maps_network_apk_pin = 'f66dfd858b52c1b7da9c2bac635106cc33a956a425860b86527cdc909e88ad43'
const auth_worker_api_runner = '/Users/alex/.local/state/vinix/android/auth-worker-api-run-2026-10-29-r1/run'
const auth_worker_api_runner_pin = '35bb212db62c2734ecf1198deddee04f20a8761d4b3cfb383cd978d4670856e9'
const maps_network_v2_apk = '/Users/alex/.local/state/vinix/android/maps-network-tls-v2-fixture-2026-10-29-r1/probe.apk'
const maps_network_v2_apk_pin = 'abfa8127b920dd7156d3cdee056a98d725411c6b5b2f8cb081149393c0b9c051'
const binder_identity_api_runner = '/Users/alex/.local/state/vinix/android/binder-identity-api-run-2026-10-29-r1/run'
const binder_identity_api_runner_pin = '29975834bca029b057df515c1210d9121e481c8b999bbcb2f4f7af8495b6c922'
const maps_network_v3_apk = '/Users/alex/.local/state/vinix/android/maps-network-tls-v3-fixture-2026-10-29-r1/probe.apk'
const maps_network_v3_apk_pin = 'bd07eddf7594fd6cc6b90b984baf7ee5855af0fc56ee0322fbc45ea318cf393a'
const file_limit = 32 * 1024 * 1024
const request_limit = 12
const seconds_limit = 600
const scope = 'Credential-free generic ART fixture transfer only; no Google account sign-in evidence.'

struct Asset {
	url string
	path string
	sha256 string
	bytes u64
}

struct Event {
	request int
	status int
	url string
	error string
}

struct Outcome {
	success bool
	reason string
	events []Event
	completed []string
}

fn valid_digest(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn external(root string) ! {
	parent := os.dir(root)
	name := os.file_name(root)
	if !root.starts_with('/') || root.contains_any('\x00\r\n\\') || name in ['', '.', '..']
		|| os.real_path(parent) != parent || parent + '/' + name != root {
		return error('canonical absolute external output required')
	}
	mut ancestor := parent
	for {
		if os.exists(ancestor + '/.git') { return error('output must be outside Git checkouts') }
		if ancestor == '/' { break }
		ancestor = os.dir(ancestor)
	}
}

fn create(path string) !int {
	fd := C.open(path.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('fresh private output file required: ' + path) }
	return fd
}

fn write_fd(fd int, data []u8) ! {
	mut offset := 0
	for offset < data.len {
		n := unsafe { C.write(fd, &u8(data.data) + offset, uint(data.len - offset)) }
		if n <= 0 { return error('file write failed') }
		offset += int(n)
	}
}

fn write_json(path string, value string) ! {
	fd := create(path)!
	defer { C.close(fd) }
	write_fd(fd, (value + '\n').bytes())!
}

fn open_bounded(path string) !(int, u64) {
	if os.real_path(path) != path { return error('canonical regular input required') }
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot open input') }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || st.st_mode & C.S_IFMT != C.S_IFREG
		|| st.st_size <= 0 || st.st_size > file_limit {
		C.close(fd)
		return error('nonempty regular input at most 32 MiB required')
	}
	return fd, u64(st.st_size)
}

// Snapshot only the selected bounded inputs. Verify bytes while copying; serving never
// resolves a request path to a filesystem path or opens another input.
fn snapshot(input Asset, output string) !Asset {
	if !valid_digest(input.sha256) { return error('pinned fixture digest required') }
	fd, size := open_bounded(input.path)!
	defer { C.close(fd) }
	out := create(output)!
	defer { C.close(out) }
	mut hash := sha256.new()
	mut count := u64(0)
	mut buffer := []u8{len: 65536}
	for {
		n := C.read(fd, buffer.data, uint(buffer.len))
		if n < 0 { return error('input read failed') }
		if n == 0 { break }
		count += u64(n)
		if count > size { return error('input grew during snapshot') }
		hash.write(buffer[..int(n)])!
		write_fd(out, buffer[..int(n)])!
	}
	if count != size || hash.sum([]u8{}).hex() != input.sha256 {
		return error('input size or SHA256 differs')
	}
	os.chmod(output, 0o400)!
	return Asset{url: input.url, path: output, sha256: input.sha256, bytes: count}
}

fn parse_request(header string) !(string, int) {
	if header.len > 8192 || !header.ends_with('\r\n\r\n')
		|| header.contains('\x00') || header.bytes().any(it < 32 && it !in [u8(`\r`), `\n`, `\t`]) {
		return error('invalid bounded HTTP headers')
	}
	lines := header[..header.len - 4].split('\r\n')
	parts := lines[0].split(' ')
	if parts.len != 3 || parts[2] !in ['HTTP/1.0', 'HTTP/1.1'] { return error('invalid request line') }
	if parts[0] != 'GET' { return parts[1], 405 }
	for line in lines[1..] {
		index := line.index(':') or { return error('invalid header') }
		if index == 0 { return error('empty header name') }
		name := line[..index].to_lower()
		if name == 'transfer-encoding' || (name == 'content-length' && line[index + 1..].trim_space() != '0') {
			return error('request body is not allowed')
		}
	}
	return parts[1], 200
}

fn read_request(mut connection net.TcpConn) !string {
	mut header := []u8{cap: 8192}
	mut buffer := []u8{len: 1024}
	for header.len < 8192 {
		n := connection.read(mut buffer[..int_min(buffer.len, 8192 - header.len)])!
		if n <= 0 { return error('incomplete request') }
		header << buffer[..n]
		if end := header.bytestr().index('\r\n\r\n') {
			if end + 4 != header.len { return error('request body or pipelining rejected') }
			return header.bytestr()
		}
	}
	return error('request headers exceed 8 KiB')
}

fn status(mut connection net.TcpConn, code int) ! {
	label := if code == 405 { 'Method Not Allowed' } else if code == 404 { 'Not Found' } else { 'Bad Request' }
	connection.write_string('HTTP/1.1 ' + code.str() + ' ' + label + '\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')!
}

fn send_asset(mut connection net.TcpConn, asset Asset, deadline time.Time) ! {
	fd, size := open_bounded(asset.path)!
	defer { C.close(fd) }
	if size != asset.bytes { return error('snapshot size changed') }
	connection.write_string('HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: '
		+ size.str() + '\r\nX-Content-SHA256: ' + asset.sha256 + '\r\nConnection: close\r\n\r\n')!
	mut hash := sha256.new()
	mut count := u64(0)
	mut buffer := []u8{len: 65536}
	for {
		if time.now() >= deadline { return error('absolute transfer deadline expired') }
		n := C.read(fd, buffer.data, uint(buffer.len))
		if n < 0 { return error('snapshot read failed') }
		if n == 0 { break }
		count += u64(n)
		if count > size { return error('snapshot grew') }
		hash.write(buffer[..int(n)])!
		if connection.write(buffer[..int(n)])! != int(n) { return error('short HTTP body write') }
	}
	if count != size || hash.sum([]u8{}).hex() != asset.sha256 { return error('snapshot SHA256 changed') }
}

fn serve_loop(mut listener net.TcpListener, assets []Asset, limit int, deadline time.Time) Outcome {
	mut events := []Event{}
	mut complete := []string{}
	listener.set_accept_deadline(deadline)
	for number in 1 .. limit + 1 {
		mut connection := listener.accept() or {
			return Outcome{reason: 'accept failed or deadline expired: ' + err.msg(), events: events, completed: complete}
		}
		read_deadline := time.now().add(5 * time.second)
		connection.set_read_deadline(if read_deadline < deadline { read_deadline } else { deadline })
		connection.set_write_deadline(deadline)
		mut code := 400
		mut url := ''
		mut message := ''
		header := read_request(mut connection) or { message = err.msg(); '' }
		if header != '' {
			url, code = parse_request(header) or { message = err.msg(); '', 400 }
		}
		mut found := -1
		if code == 200 {
			for index, asset in assets { if url == asset.url { found = index; break } }
			if found < 0 { code = 404 }
		}
		if code == 200 {
			send_asset(mut connection, assets[found], deadline) or { message = err.msg() }
			if message == '' && url !in complete { complete << url }
		} else {
			status(mut connection, code) or { message = err.msg() }
		}
		connection.close() or { message += ' close: ' + err.msg() }
		events << Event{number, code, url, message}
		if complete.len == assets.len { return Outcome{success: true, events: events, completed: complete} }
		if time.now() >= deadline { return Outcome{reason: 'absolute deadline expired', events: events, completed: complete} }
	}
	return Outcome{reason: 'request limit exhausted', events: events, completed: complete}
}

fn pinned_assets() []Asset {
	return [Asset{url: '/service-query-run', path: runner_path, sha256: runner_pin},
		Asset{url: '/client.apk', path: fixture_root + '/client/probe.apk', sha256: client_pin},
		Asset{url: '/disabled.apk', path: fixture_root + '/disabled/probe.apk', sha256: disabled_pin}]
}

fn direct_boot_assets() []Asset {
	return [Asset{url: '/direct-boot-run', path: direct_boot_runner, sha256: direct_boot_runner_pin},
		Asset{url: '/client.apk', path: direct_boot_fixture + '/client/probe.apk', sha256: direct_boot_client_pin},
		Asset{url: '/disabled.apk', path: direct_boot_fixture + '/disabled/probe.apk', sha256: direct_boot_disabled_pin}]
}

fn credential_storage_assets() []Asset {
	return [Asset{url: '/credential-storage-run', path: credential_storage_runner, sha256: credential_storage_runner_pin},
		Asset{url: '/client.apk', path: credential_storage_fixture + '/client/probe.apk', sha256: credential_storage_client_pin},
		Asset{url: '/disabled.apk', path: credential_storage_fixture + '/disabled/probe.apk', sha256: credential_storage_disabled_pin}]
}

fn broadcast_result_assets() []Asset {
	return [Asset{url: '/broadcast-result-run', path: broadcast_result_runner, sha256: broadcast_result_runner_pin},
		Asset{url: '/client.apk', path: broadcast_result_fixture + '/client/probe.apk', sha256: broadcast_result_client_pin},
		Asset{url: '/disabled.apk', path: broadcast_result_fixture + '/disabled/probe.apk', sha256: broadcast_result_disabled_pin}]
}

fn onboarding_api_assets() []Asset {
	return [Asset{url: '/onboarding-api-run', path: onboarding_api_runner, sha256: onboarding_api_runner_pin},
		Asset{url: '/child-attach.apk', path: child_attach_apk, sha256: child_attach_apk_pin},
		Asset{url: '/settings-global.apk', path: settings_global_apk, sha256: settings_global_apk_pin}]
}

fn application_restrictions_assets() []Asset {
	return [Asset{url: '/application-restrictions-run', path: application_restrictions_runner, sha256: application_restrictions_runner_pin},
		Asset{url: '/application-restrictions.apk', path: application_restrictions_apk, sha256: application_restrictions_apk_pin}]
}

fn auth_exception_api_assets() []Asset {
	return [Asset{url: '/auth-exception-api-run', path: auth_exception_api_runner, sha256: auth_exception_api_runner_pin},
		Asset{url: '/authenticator-exception.apk', path: authenticator_exception_apk, sha256: authenticator_exception_apk_pin},
		Asset{url: '/maps-network.apk', path: maps_network_apk, sha256: maps_network_apk_pin}]
}

fn auth_worker_api_assets() []Asset {
	return [Asset{url: '/auth-worker-api-run', path: auth_worker_api_runner, sha256: auth_worker_api_runner_pin},
		Asset{url: '/authenticator-exception.apk', path: authenticator_exception_apk, sha256: authenticator_exception_apk_pin},
		Asset{url: '/maps-network-v2.apk', path: maps_network_v2_apk, sha256: maps_network_v2_apk_pin}]
}

fn binder_identity_api_assets() []Asset {
	return [Asset{url: '/binder-identity-api-run', path: binder_identity_api_runner, sha256: binder_identity_api_runner_pin},
		Asset{url: '/authenticator-exception.apk', path: authenticator_exception_apk, sha256: authenticator_exception_apk_pin},
		Asset{url: '/maps-network-v3.apk', path: maps_network_v3_apk, sha256: maps_network_v3_apk_pin}]
}

fn serve(root string, port string, is_direct_boot bool, is_credential_storage bool, is_broadcast_result bool, is_onboarding_api bool, is_application_restrictions bool, is_auth_exception_api bool, is_auth_worker_api bool, is_binder_identity_api bool) ! {
	$if !net_nonblocking_sockets ? { return error('build with -d net_nonblocking_sockets for socket deadlines') }
	external(root)!
	if port == '' || port.len > 5 || !port.bytes().all(it >= `0` && it <= `9`)
		|| port.u64() > 65535 || port != port.u64().str() { return error('canonical port 0..65535 required') }
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh private output directory required') }
	inputs := if is_binder_identity_api { binder_identity_api_assets() } else if is_auth_worker_api { auth_worker_api_assets() } else if is_auth_exception_api { auth_exception_api_assets() } else if is_application_restrictions { application_restrictions_assets() } else if is_onboarding_api { onboarding_api_assets() } else if is_broadcast_result { broadcast_result_assets() } else if is_credential_storage { credential_storage_assets() } else if is_direct_boot { direct_boot_assets() } else { pinned_assets() }
	mut assets := []Asset{}
	for asset in inputs { assets << snapshot(asset, root + asset.url)! }
	mut listener := net.listen_tcp(.ip, '127.0.0.1:' + port)!
	defer { listener.close() or {} }
	address := listener.addr()!.str()
	deadline := time.now().add(seconds_limit * time.second)
	write_json(root + '/ready.json', json2.encode({
		'kind': json2.Any(if is_binder_identity_api { 'vinix-binder-identity-api-http-v1' } else if is_auth_worker_api { 'vinix-auth-worker-api-http-v1' } else if is_auth_exception_api { 'vinix-auth-exception-api-http-v1' } else if is_application_restrictions { 'vinix-application-restrictions-http-v1' } else if is_onboarding_api { 'vinix-onboarding-api-http-v1' } else if is_broadcast_result { 'vinix-broadcast-result-http-v1' } else if is_credential_storage { 'vinix-credential-storage-http-v1' } else if is_direct_boot { 'vinix-direct-boot-http-v1' } else { 'vinix-service-query-http-v1' })
		'scope': json2.Any(scope)
		'address': json2.Any(address)
		'deadline_utc': json2.Any(deadline.str())
		'request_limit': json2.Any(request_limit)
		'inputs': json2.decode[json2.Any](json2.encode(inputs))!
		'snapshots': json2.decode[json2.Any](json2.encode(assets))!
	}, prettify: true))!
	println('SERVICE-QUERY-HTTP READY ' + address)
	flush_stdout()
	result := serve_loop(mut listener, assets, request_limit, deadline)
	write_json(root + '/result.json', json2.encode(result, prettify: true))!
	if !result.success { return error(result.reason) }
	println(if is_application_restrictions { 'SERVICE-QUERY-HTTP PASS two pinned files transferred' } else { 'SERVICE-QUERY-HTTP PASS three pinned files transferred' })
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	is_direct_boot := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--direct-boot'
	is_credential_storage := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--credential-storage'
	is_broadcast_result := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--broadcast-result'
	is_onboarding_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--onboarding-apis'
	is_application_restrictions := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--application-restrictions'
	is_auth_exception_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--auth-exception-apis'
	is_auth_worker_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--auth-worker-apis'
	is_binder_identity_api := os.args.len == 5 && os.args[1] == 'serve' && os.args[2] == '--binder-identity-apis'
	if !is_direct_boot && !is_credential_storage && !is_broadcast_result && !is_onboarding_api && !is_application_restrictions && !is_auth_exception_api && !is_auth_worker_api && !is_binder_identity_api && (os.args.len != 4 || os.args[1] != 'serve') {
		eprintln('usage: service-query-transfer serve [--direct-boot|--credential-storage|--broadcast-result|--onboarding-apis|--application-restrictions|--auth-exception-apis|--auth-worker-apis|--binder-identity-apis] FRESH_EXTERNAL_DIR PORT | --self-test FRESH_EXTERNAL_DIR')
		exit(2)
	}
	offset := if is_direct_boot || is_credential_storage || is_broadcast_result || is_onboarding_api || is_application_restrictions || is_auth_exception_api || is_auth_worker_api || is_binder_identity_api { 1 } else { 0 }
	serve(os.args[2 + offset], os.args[3 + offset], is_direct_boot, is_credential_storage, is_broadcast_result, is_onboarding_api, is_application_restrictions, is_auth_exception_api, is_auth_worker_api, is_binder_identity_api) or { eprintln(err); exit(1) }
}

fn get(address string, request string) !string {
	mut connection := net.dial_tcp(address)!
	defer { connection.close() or {} }
	connection.set_read_deadline(time.now().add(2 * time.second))
	connection.set_write_deadline(time.now().add(2 * time.second))
	connection.write_string(request)!
	mut result := []u8{}
	mut buffer := []u8{len: 65536}
	for {
		n := connection.read(mut buffer) or { break }
		if n == 0 { break }
		if result.len + n > 256 * 1024 { return error('test response exceeds bound') }
		result << buffer[..n]
	}
	return result.bytestr()
}

fn self_test(root string) ! {
	$if !net_nonblocking_sockets ? { return error('self-test requires nonblocking sockets') }
	external(root)!
	if unsafe { C.mkdir(root.str, 0o700) } != 0 { return error('fresh self-test output required') }
	for bad in [['serve', '--binder-identity-apis'],
		['serve', '--binder-identity-apis', root + '/must-not-exist'],
		['serve', '--binder-identity-apis-other', root + '/must-not-exist', '0'],
		['serve', '--binder-identity-apis', root + '/must-not-exist', '0', 'extra']] {
		mut argv := [os.executable()]
		argv << bad
		result := os.exec(argv)
		assert result.exit_code != 0, 'malformed Binder identity transfer CLI accepted'
		assert !os.exists(root + '/must-not-exist'), 'malformed CLI created transfer output'
	}
	for port in ['', '00', '-1', '65536', '0x10'] {
		result := os.exec([os.executable(), 'serve', '--binder-identity-apis', root + '/must-not-exist', port])
		assert result.exit_code == 1 && result.output.contains('canonical port 0..65535 required')
		assert !os.exists(root + '/must-not-exist'), 'invalid port created transfer output'
	}
	assert pinned_assets().len == 3 && direct_boot_assets().len == 3 && credential_storage_assets().len == 3
	assert broadcast_result_assets().len == 3
	assert pinned_assets()[0].url == '/service-query-run' && direct_boot_assets()[0].url == '/direct-boot-run'
	assert credential_storage_assets()[0].url == '/credential-storage-run'
	assert broadcast_result_assets()[0].url == '/broadcast-result-run'
	assert onboarding_api_assets().len == 3
	assert onboarding_api_assets().map(it.url) == ['/onboarding-api-run', '/child-attach.apk', '/settings-global.apk']
	assert application_restrictions_assets().len == 2
	assert application_restrictions_assets().map(it.url) == ['/application-restrictions-run', '/application-restrictions.apk']
	assert auth_exception_api_assets().len == 3
	assert auth_exception_api_assets().map(it.url) == ['/auth-exception-api-run', '/authenticator-exception.apk', '/maps-network.apk']
	assert auth_worker_api_assets().len == 3
	assert auth_worker_api_assets().map(it.url) == ['/auth-worker-api-run', '/authenticator-exception.apk', '/maps-network-v2.apk']
	assert binder_identity_api_assets().len == 3
	assert binder_identity_api_assets().map(it.url) == ['/binder-identity-api-run', '/authenticator-exception.apk', '/maps-network-v3.apk']
	for index, asset in binder_identity_api_assets() {
		assert valid_digest(asset.sha256)
		if index == 1 {
			assert asset == auth_exception_api_assets()[1] && asset == auth_worker_api_assets()[1]
		} else {
			for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets(), auth_worker_api_assets()] {
				for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 && asset.url != old.url }
			}
		}
	}
	for index, asset in auth_worker_api_assets() {
		assert valid_digest(asset.sha256)
		if index == 1 {
			assert asset == auth_exception_api_assets()[1]
		} else {
			for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets(), auth_exception_api_assets()] {
				for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
			}
		}
	}
	for asset in auth_exception_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets(), application_restrictions_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
		}
	}
	for asset in application_restrictions_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets(), onboarding_api_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
		}
	}
	for asset in onboarding_api_assets() {
		assert valid_digest(asset.sha256)
		for older in [pinned_assets(), direct_boot_assets(), credential_storage_assets(), broadcast_result_assets()] {
			for old in older { assert asset.path != old.path && asset.sha256 != old.sha256 }
		}
	}
	for index, asset in direct_boot_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path
	}
	for index, asset in credential_storage_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.sha256 != direct_boot_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path && asset.path != direct_boot_assets()[index].path
	}
	for index, asset in broadcast_result_assets() {
		assert valid_digest(asset.sha256) && asset.sha256 != pinned_assets()[index].sha256
		assert asset.sha256 != direct_boot_assets()[index].sha256
		assert asset.sha256 != credential_storage_assets()[index].sha256
		assert asset.path != pinned_assets()[index].path && asset.path != direct_boot_assets()[index].path
		assert asset.path != credential_storage_assets()[index].path
	}
	for bad in ['POST /client.apk HTTP/1.1\r\n\r\n', 'HEAD /client.apk HTTP/1.0\r\n\r\n'] {
		_, code := parse_request(bad)!
		assert code == 405
	}
	for bad in ['GET / HTTP/2\r\n\r\n', 'GET / HTTP/1.1\r\nContent-Length: 1\r\n\r\n',
		'GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n', 'x'.repeat(8193)] {
		if _, _ := parse_request(bad) { return error('unsafe request accepted') }
	}
	body := 'binary\x00\xff\n'.repeat(20000)
	input := root + '/input'
	os.write_file(input, body)!
	asset := snapshot(Asset{url: '/one', path: input, sha256: sha256.hexhash(body)}, root + '/snapshot')!
	if _ := snapshot(Asset{path: input, sha256: '0'.repeat(64)}, root + '/wrong-pin') { return error('wrong input pin accepted') }
	os.symlink(input, root + '/link')!
	if _, _ := open_bounded(root + '/link') { return error('symlink input accepted') }
	os.write_file(root + '/empty', '')!
	if _, _ := open_bounded(root + '/empty') { return error('empty input accepted') }
	if _ := snapshot(Asset{path: input, sha256: sha256.hexhash(body)}, root + '/snapshot') { return error('existing output accepted') }
	assert os.lstat(root + '/snapshot')!.mode & 0o777 == 0o400
	assets := [asset, Asset{...asset, url: '/two'}, Asset{...asset, url: '/three'}]
	mut listener := net.listen_tcp(.ip, '127.0.0.1:0')!
	address := listener.addr()!.str()
	worker := spawn serve_loop(mut listener, assets, 7, time.now().add(5 * time.second))
	for request in ['POST /one HTTP/1.1\r\n\r\n', 'GET /../input HTTP/1.1\r\n\r\n',
		'GET /%2e%2e/input HTTP/1.1\r\n\r\n', 'GET /one?query HTTP/1.1\r\n\r\n'] {
		response := get(address, request)!
		assert !response.starts_with('HTTP/1.1 200')
		assert response.ends_with('\r\n\r\n')
	}
	for name in ['/one', '/two', '/three'] {
		response := get(address, 'GET ' + name + ' HTTP/1.0\r\n\r\n')!
		assert response.starts_with('HTTP/1.1 200 OK\r\n')
		assert response.all_after('\r\n\r\n') == body
	}
	result := worker.wait()
	listener.close()!
	assert result.success && result.events.len == 7 && result.completed.len == 3
	mut paired := net.listen_tcp(.ip, '127.0.0.1:0')!
	paired_address := paired.addr()!.str()
	paired_worker := spawn serve_loop(mut paired, assets[..2], 2, time.now().add(5 * time.second))
	for name in ['/one', '/two'] {
		response := get(paired_address, 'GET ' + name + ' HTTP/1.0\r\n\r\n')!
		assert response.starts_with('HTTP/1.1 200 OK\r\n') && response.all_after('\r\n\r\n') == body
	}
	paired_result := paired_worker.wait()
	paired.close()!
	assert paired_result.success && paired_result.events.len == 2 && paired_result.completed.len == 2
	mut limited := net.listen_tcp(.ip, '127.0.0.1:0')!
	limited_address := limited.addr()!.str()
	limited_worker := spawn serve_loop(mut limited, assets, 1, time.now().add(time.second))
	get(limited_address, 'GET /missing HTTP/1.0\r\n\r\n')!
	limited_result := limited_worker.wait()
	limited.close()!
	assert !limited_result.success && limited_result.reason == 'request limit exhausted'
	mut idle := net.listen_tcp(.ip, '127.0.0.1:0')!
	watch := time.new_stopwatch()
	idle_result := serve_loop(mut idle, assets, 1, time.now().add(50 * time.millisecond))
	idle.close()!
	assert !idle_result.success && watch.elapsed() < time.second
	write_json(root + '/self-test.json', json2.encode(result, prettify: true))!
	println('SERVICE-QUERY-HTTP SELF-TEST PASS pinned snapshots exact binary multi-buffer GET-only traversal request-limit absolute accept deadline')
}
