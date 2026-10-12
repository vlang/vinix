// SPDX-License-Identifier: GPL-2.0-or-later
module androidrunfixtures

import androidhost as ah
import androidrun
import cachecli
import hosttest
import json2
import net.unix
import os

@[heap]
struct QmpFixture {
mut:
	listener &unix.StreamListener = unsafe { nil }
	shift    bool
	keys     string
	recorded []ah.Value
}

fn qmp_line(mut connection unix.StreamConn) !map[string]ah.Value {
	mut bytes := []u8{}
	mut buffer := []u8{len: 1}
	for {
		count := connection.read(mut buffer)!
		if count == 0 { return error('fixture EOF') }
		if buffer[0] == `\n` { break }
		bytes << buffer
	}
	return json2.decode[ah.Value](bytes.bytestr(), strict: true)!.object()
}

fn serial(data string) ! {
	mut output := os.stdout()
	unsafe { output.write_full_buffer(data.str, usize(data.len))! }
	output.flush()
}

fn qmp_exchange(mut fixture QmpFixture) ! {
	mut connection := fixture.listener.accept()!
	defer { connection.close() or {} }
	connection.write_string('{"QMP":{}}\n')!
	assert ah.field(qmp_line(mut connection)!, 'execute').text() == 'qmp_capabilities'
	connection.write_string('{"return":{}}\n')!
	request := qmp_line(mut connection)!
	fixture.recorded << ah.Value(request)
	state := os.getenv('VINIX_FIXTURE_QMP').all_before_last('/')
	os.write_file(state + '/events.json', androidrun.dump_json(ah.Value(fixture.recorded), 2))!
	command := ah.field(request, 'execute').text()
	if command == 'screendump' {
		if os.getenv('VINIX_FIXTURE_MODE') == 'shot' {
			connection.write_string('{"error":{"desc":"controlled screenshot failure"}}\n')!
			return
		}
		path := ah.field(ah.field(request, 'arguments').object(), 'filename').text()
		mut pixels := 'P6\n2 1\n255\n'.bytes()
		pixels << [u8(0), 1, 255, 13, 10, 32]
		os.write_file_array(path, pixels)!
	} else if command == 'input-send-event' {
		if os.getenv('VINIX_FIXTURE_MODE') == 'io' {
			connection.write_string('{"error":{"desc":"controlled input failure"}}\n')!
			return
		}
		for event in ah.field(ah.field(request, 'arguments').object(), 'events').items() {
			row := event.object()
			if ah.field(row, 'type').text() != 'key' { continue }
			data := ah.field(row, 'data').object()
			name := ah.field(ah.field(data, 'key').object(), 'data').text()
			down := ah.field(data, 'down') == ah.Value(true)
			if name == 'shift' {
				fixture.shift = down
				continue
			}
			if down { continue }
			fixture.keys += if name == 'equal' && fixture.shift { '+' } else { name }
			serial('ANDROID-INPUT ' + fixture.keys + '\n')!
			if fixture.keys == os.getenv('VINIX_FIXTURE_KEYS') {
				// Exercise the real reader while input and QMP are live. The
				// latest complete acknowledgement remains after the lookback.
				serial('serial-drain-fixture '.repeat(60000) + '\nANDROID-INPUT ' + fixture.keys + '\nANDROID-PASS\n')!
			}
		}
	}
	connection.write_string('{"event":"ignored"}\n{"return":{}}\n')!
}

fn qmp_worker(mut fixture QmpFixture) {
	for {
		qmp_exchange(mut fixture) or {
			eprintln(err.msg())
			return
		}
	}
}

fn start_qmp_fixture() ! {
	mut fixture := &QmpFixture{ listener: unix.listen_stream(os.getenv('VINIX_FIXTURE_QMP'))! }
	spawn qmp_worker(mut fixture)
}

fn session_plan(args map[string]ah.Value, _ ah.Value) !androidrun.Plan {
	mut environment := os.environ()
	environment['VINIX_FIXTURE_TRANSCRIPT'] = ah.field(args, 'fixture_transcript').text().bytes().hex()
	environment['VINIX_FIXTURE_QMP'] = ah.field(args, 'state_dir').text() + '/qmp.sock'
	environment['VINIX_FIXTURE_KEYS'] = ah.field(args, 'keys').text()
	environment['VINIX_FIXTURE_MODE'] = ah.field(args, 'fixture_mode').text()
	return androidrun.Plan{ command: [os.executable(), '--mock-vm'], environment: environment, directory: ah.field(args, 'repo').text() }
}

pub fn session_tests(root string, work string) ! {
	os.mkdir(work)!
	for mode in ['calc', 'obs', 'io', 'shot'] {
		directory := work + '/' + mode
		mut args := inputs(root, directory)!
		args['interactive'] = ah.Value(false)
		args['observe'] = ah.Value(mode == 'obs')
		args['keys'] = ah.Value('1+2')
		args['expect'] = ah.Value('3')
		args['timeout'] = ah.Value(60)
		args['fixture_mode'] = ah.Value(mode)
		args['fixture_transcript'] = ah.Value(if mode == 'obs' {
			'ANDROID-READY\nANDROID-OBSERVED seconds=30 functionality=unchecked\n'
		} else {
			'ANDROID-READY\n'
		})
		mut context := androidrun.Context{ root: root, args: args, plan_hook: session_plan }
		guard := cachecli.own_commands()
		status := context.run_session(ah.Value(json2.Null{}))!
		guard.close()
		context.close()
		result := androidrun.load_json(os.read_file(directory + '/session/result.json')!)!.object()
		assert status == if mode in ['calc', 'obs'] { 0 } else { 1 }
		assert ah.field(result, 'observed') == ah.Value(mode == 'obs')
		assert ah.field(result, 'passed') == if mode == 'obs' {
			ah.Value(json2.Null{})
		} else {
			ah.Value(mode == 'calc')
		}
		assert !os.exists(directory + '/session/qmp.sock')
		if mode == 'calc' {
			assert ah.encode(ah.field(result, 'key_retries')) == '0'
			assert os.file_size(directory + '/session/serial.log') > 1200000
			assert os.read_file(directory + '/session/serial.log')!.contains('ANDROID-INPUT 1+2\nANDROID-PASS\n')
			assert os.is_file(directory + '/session/ready.png') && os.is_file(directory + '/session/application.png')
		} else if mode == 'obs' {
			assert !os.exists(directory + '/session/ready.png') && os.is_file(directory + '/session/application.png')
			assert ah.field(result, 'check').text() == 'window-observation'
		} else {
			assert ah.field(result, 'failure').text() == if mode == 'shot' {
				'screenshot failed'
			} else {
				'keyboard input failed: {"desc":"controlled input failure"}'
			}
		}
		if mode != 'shot' {
			assert !os.exists(directory + '/session/application.ppm')
			assert hosttest.sha(directory + '/session/application.png')! != ''
		}
	}
	os.write_file(work + '/passed', 'PASS\n')!
	eprintln('NATIVE ANDROID SESSION / actual PTY and QMP calculator acknowledgements, shifted key, live 1.2 MB serial drain, ready and final screenshots / generic observation / input and screenshot failure cleanup: PASS')
}
