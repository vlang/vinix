import androidrun
import androidhost as ah
import os
import time

fn main() {
	assert os.args.len <= 2, 'usage: trace-input [attempt-number]'
	attempt := if os.args.len == 2 { os.args[1] } else { '233' }
	assert attempt.len > 0 && attempt.bytes().all(it >= `0` && it <= `9`)
	path := 'build/android-maps/attempt' + attempt + '/google-maps/'
	trace_path := os.abs_path(path + 'keyboard-trace.log')
	assert !os.exists(trace_path), 'refusing to replace existing trace'
	mut receipt := os.create(path + 'keyboard-trace-enable.log')!
	defer { receipt.close() }
	begin := time.now().str() + ' UTC+3 TRACE-ENABLE BEGIN\n'
	print(begin)
	receipt.write_string(begin)!
	pid := os.read_file(path + 'qemu.pid')!.trim_space()
	assert pid.len > 0 && pid.bytes().all(it >= `0` && it <= `9`)
	stderr_info := os.exec(['lsof', '-a', '-p', pid, '-d', '2'])
	receipt.write_string('QEMU pid=' + pid + ' stderr-descriptor:\n' + stderr_info.output + '\n')!
	mut monitor := androidrun.connect_monitor(path + 'qmp.sock', 20)!
	defer { monitor.close() }
	// This QEMU has CONFIG_TRACE_LOG: route its trace log to a retained file.
	response := monitor.command('human-monitor-command', {
		'command-line': ah.Value('logfile ' + trace_path)
	})!
	receipt.write_string('LOGFILE ' + trace_path + ' reply=' + ah.encode(response) + '\n')!
	assert response.text().trim_space() == '', 'logfile command returned a diagnostic'
	for name in ['virtio_input_queue_full', 'input_event_key_qcode', 'input_event_sync'] {
		before := monitor.command('trace-event-get-state', {'name': ah.Value(name)})!
		receipt.write_string('BEFORE ' + name + ' ' + ah.encode(before) + '\n')!
		monitor.command('trace-event-set-state', {
			'name': ah.Value(name)
			'enable': ah.Value(true)
		})!
		after := monitor.command('trace-event-get-state', {'name': ah.Value(name)})!
		line := 'ENABLED ' + name + ' ' + ah.encode(after) + '\n'
		print(line)
		receipt.write_string(line)!
		assert ah.encode(after).contains('enabled'), 'trace event did not enable'
	}
	end := time.now().str() + ' UTC+3 TRACE-ENABLE END path=' + trace_path + '\n'
	print(end)
	receipt.write_string(end)!
}
