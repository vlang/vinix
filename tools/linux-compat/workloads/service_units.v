// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import encoding.hex
import net
import net.unix
import os
import strconv
import time
import desktop.sessionipc

struct ServiceUnitResult {
	unit_sha256            string
	broker_sha256          string
	first_pid              int
	restarted_pid          int
	restored_pid           int
	response               string
	unsupported_rejected   bool
	unauthorized_rejected  bool
	active_remove_rejected bool
	configuration_restored bool
	removed                bool
	broker_retired         bool
	requests               []ServiceUnitRequest
}

struct ServiceUnitRequest {
	arguments []string
	reply     string
	rejected  bool
}

fn service_pid(record string, name string) !int {
	encoded := hex.encode(name.bytes())
	for line in record.split_into_lines() {
		fields := line.split('\t')
		if fields.len != 8 || fields[0] != 'service' || fields[2] != encoded { continue }
		return strconv.atoi(fields[4])!
	}
	return 0
}

fn (mut suite Suite) service_control(arguments []string) !string {
	reply := sessionipc.session_call(arguments[0], arguments[1..]) or {
		if err.msg() == 'session request rejected' {
			suite.unit_requests << ServiceUnitRequest{arguments, 'error\tdenied', true}
		}
		return err
	}
	suite.unit_requests << ServiceUnitRequest{arguments, reply, false}
	return reply
}

fn (mut suite Suite) public_service_control(arguments []string) !string {
	path := suite.work + '/unit-runtime/vinix-session.' + C.getuid().str() + '/broker'
	mut connection := unix.connect_stream(path)!
	defer { connection.close() or {} }
	connection.set_read_timeout(3 * time.second)
	connection.set_write_timeout(3 * time.second)
	mut request := arguments[0]
	for argument in arguments[1..] { request += '\t' + hex.encode(argument.bytes()) }
	length := u32(request.len)
	header := [u8(length), u8(length >> 8), u8(length >> 16), u8(length >> 24)]!
	expect(connection.write(header[..])! == 4 && connection.write_string(request)! == request.len,
		'short service request')!
	mut response_header := [4]u8{}
	mut offset := 0
	for offset < 4 {
		n := connection.read_ptr(unsafe { &response_header[offset] }, 4 - offset)!
		expect(n > 0, 'truncated service response header')!
		offset += n
	}
	size := int(u32(response_header[0]) | (u32(response_header[1]) << 8) |
		(u32(response_header[2]) << 16) | (u32(response_header[3]) << 24))
	expect(size > 0 && size <= 256 * 1024, 'invalid service response size')!
	mut bytes := []u8{len: size}
	offset = 0
	for offset < size {
		n := connection.read_ptr(unsafe { &bytes[offset] }, size - offset)!
		expect(n > 0, 'truncated service response')!
		offset += n
	}
	reply := bytes.bytestr()
	rejected := reply.starts_with('error\t')
	suite.unit_requests << ServiceUnitRequest{arguments, reply, rejected}
	if rejected { return error('service broker rejected the request') }
	return reply
}

fn (mut suite Suite) service_control_on(arguments []string, public bool) !string {
	if public { return suite.public_service_control(arguments) }
	return suite.service_control(arguments)
}

fn (mut suite Suite) rejected_service_control(arguments []string, public bool) ! {
	count := suite.unit_requests.len
	reply := suite.service_control_on(arguments, public) or {
		expect(suite.unit_requests.len == count + 1 && suite.unit_requests.last().rejected,
			'missing explicit service rejection receipt')!
		return
	}
	return error('unsupported service request succeeded: ' + reply)
}

fn (mut suite Suite) wait_service_pid(name string, previous int, stopped bool) !int {
	watch := time.new_stopwatch()
	for {
		record := suite.service_control(['services'])!
		pid := service_pid(record, name)!
		if (stopped && pid == 0) || (!stopped && pid > 0 && pid != previous) { return pid }
		if watch.elapsed() > 10 * time.second { return error('service lifecycle did not converge') }
		time.sleep(100 * time.millisecond)
	}
	return error('unreachable')
}

fn unit_http_response(content string) !string {
	watch := time.new_stopwatch()
	for {
		mut conn := net.dial_tcp('127.0.0.1:19017') or {
			if watch.elapsed() > 10 * time.second {
				return error('imported HTTP unit did not become ready')
			}
			time.sleep(100 * time.millisecond)
			continue
		}
		defer { conn.close() or {} }
		conn.set_read_timeout(2 * time.second)
		conn.write_string('GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')!
		mut bytes := [4096]u8{}
		mut response := ''
		for {
			n := conn.read(mut bytes) or { break }
			if n == 0 { break }
			response += bytes[..n].bytestr()
			if response.len > 65536 { return error('unbounded imported HTTP response') }
		}
		expect((response.starts_with('HTTP/1.0 200 ') || response.starts_with('HTTP/1.1 200 '))
			&& response.all_after('\r\n\r\n') == content, 'imported unit served incorrect data')!
		return response
	}
	return error('unreachable')
}

fn finish_service_broker(broker int) ! {
	watch := time.new_stopwatch()
	mut status := 0
	for C.waitpid(broker, &status, C.WNOHANG) != broker {
		if watch.elapsed() > 10 * time.second { return error('service broker did not shut down') }
		time.sleep(100 * time.millisecond)
	}
	sessionipc.session_close_control()
	expect(status == 0, 'service broker did not exit successfully')!
}

fn (suite Suite) start_service_broker(home string) !int {
	previous := os.environ()
	for name, value in suite.environment { os.setenv(name, value, true) }
	defer {
		for name, _ in suite.environment {
			if value := previous[name] {
				os.setenv(name, value, true)
			} else {
				os.unsetenv(name)
			}
		}
	}
	broker := sessionipc.session_start_broker_at(home, '/usr/bin/vinix-desktop') or { return error('cannot launch session broker') }
	watch := time.new_stopwatch()
	for !sessionipc.session_call_ok('ping', []) {
		if watch.elapsed() > 10 * time.second {
			C.kill(broker, C.SIGKILL)
			mut status := 0
			C.waitpid(broker, &status, 0)
			sessionipc.session_close_control()
			return error('session service broker failed to start')
		}
		time.sleep(100 * time.millisecond)
	}
	return broker
}

fn (mut suite Suite) service_units() ! {
	expect(!suite.path.starts_with('translated-'), 'unsupported: Linux unit integration requires a native broker')!
	_ = suite.command('/usr/bin/vinix-desktop', [])!
	command := suite.command('busybox-extras', [])!
	applets := suite.execute('busybox-extras', ['--list'])!
	expect('httpd' in applets.split_into_lines(), 'unsupported: BusyBox Extras has no HTTP service')!
	home := suite.work + '/unit-home'
	runtime := suite.work + '/unit-runtime'
	for directory in [home, runtime, home + '/www'] {
		os.mkdir_all(directory)!
		os.chmod(directory, 0o700)!
	}
	suite.environment['VINIX_SESSION_RUNTIME'] = runtime
	name := 'linux-http.service'
	content := 'vinix-imported-service-' + sha256.sum(home.bytes()).hex()
	os.write_file(home + '/www/index.html', content)!
	unit := '[Unit]\nDescription=Vinix HTTP qualification\n[Service]\nType=simple\nExecStart=' + command[0] +
		' httpd -f -p 127.0.0.1:19017 -h "' + home + '/www"\nRestart=on-failure\nRestartSec=0.1s\nTimeoutStopSec=1s\n[Install]\nWantedBy=default.target\n'
	os.write_file(home + '/http.service', unit)!
	os.write_file(home + '/unsupported.service', unit.replace('[Install]', 'PrivateNetwork=yes\n[Install]'))!
	config := home + '/.vinix-services'
	os.write_file(config, 'vinix-services\t1\n')!
	mut broker := suite.start_service_broker(home)!
	defer {
		if broker > 0 {
			C.kill(broker, C.SIGKILL)
			mut status := 0
			C.waitpid(broker, &status, 0)
			sessionipc.session_close_control()
		}
	}
	suite.service_control(['ping'])!
	initial := os.read_file(config)!
	suite.rejected_service_control(['service.import', name, home + '/http.service', '0'], true)!
	expect(os.read_file(config)! == initial, 'unauthorized import changed persistent state')!
	// Confirm the inherited compositor capability; public connections and
	// separate CLI children cannot acquire that authority from a matching PID.
	suite.service_control(['attach'])!
	suite.rejected_service_control(['service.import', 'unsupported.service',
		home + '/unsupported.service', '1'], false)!
	expect(os.read_file(config)! == initial, 'rejected unit changed persistent state')!
	suite.service_control(['service.import', name, home + '/http.service', '0'])!
	_ = suite.wait_service_pid(name, 0, true)!
	expect(os.read_file(config)! != initial, 'disabled import did not persist the definition')!
	if mut connection := net.dial_tcp('127.0.0.1:19017') {
		connection.close() or {}
		return error('disabled service started without a Start request')
	}
	suite.service_control(['service.enable', '0', '1'])!
	first := suite.wait_service_pid(name, 0, false)!
	_ = unit_http_response(content)!
	saved := os.read_file(config)!
	suite.rejected_service_control(['service.remove', name], false)!
	expect(os.read_file(config)! == saved, 'active removal changed persistent state')!
	expect(C.kill(first, C.SIGKILL) == 0, 'could not exercise service failure restart')!
	restarted := suite.wait_service_pid(name, first, false)!
	response := unit_http_response(content)!
	suite.service_control(['shutdown'])!
	finish_service_broker(broker)!
	broker = 0
	broker = suite.start_service_broker(home)!
	suite.service_control(['ping'])!
	suite.service_control(['attach'])!
	restored := suite.wait_service_pid(name, 0, false)!
	_ = unit_http_response(content)!
	expect(os.read_file(config)! == saved, 'broker restart changed installed definition')!
	suite.service_control(['service.enable', '0', '0'])!
	_ = suite.wait_service_pid(name, 0, true)!
	suite.service_control(['service.remove', name])!
	expect(os.read_file(config)! == initial, 'unit uninstall did not restore empty registry')!
	if mut connection := net.dial_tcp('127.0.0.1:19017') {
		connection.close() or {}
		return error('removed service kept listening')
	}
	suite.service_control(['shutdown'])!
	finish_service_broker(broker)!
	broker = 0
	broker = suite.start_service_broker(home)!
	suite.service_control(['ping'])!
	suite.service_control(['attach'])!
	record := suite.service_control(['services'])!
	expect(record.trim_space() == 'vinix-service-status\t1', 'removed unit reappeared on broker restart')!
	suite.service_control(['shutdown'])!
	finish_service_broker(broker)!
	broker = 0
	suite.service_units << ServiceUnitResult{sha256.sum(unit.bytes()).hex(), sha256.sum(os.read_bytes('/usr/bin/vinix-desktop')!).hex(), first, restarted, restored, response, true, true, true, true, true, true, suite.unit_requests}
}
