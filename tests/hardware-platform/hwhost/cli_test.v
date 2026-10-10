// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

fn test_options_take_values_either_way() {
	options := parse_options(['--arch', 'x86_64', '--kernel=/k/vinix', '--scenario', 'ahci',
		'--scenario=devices', '--timeout', '30', '--state-dir=/tmp/s', '--qemu', '/q'])!
	assert options.arch == 'x86_64'
	assert options.kernel == '/k/vinix'
	assert options.scenarios == ['ahci', 'devices']
	assert options.timeout == 30
	assert options.state_dir == '/tmp/s'
	assert options.qemu == '/q'
	assert !options.list
}

fn test_defaults() {
	options := parse_options(['--arch', 'aarch64', '--kernel', 'k'])!
	assert options.timeout == 120
	assert options.scenarios.len == 0
	assert options.state_dir == ''
}

fn test_list_needs_no_kernel() {
	options := parse_options(['--list'])!
	assert options.list
	assert parse_options(['--list', '--arch=aarch64'])!.arch == 'aarch64'
	assert parse_options(['--help'])!.help
}

fn mistake(arguments []string) string {
	parse_options(arguments) or { return err.msg() }
	return ''
}

fn test_mistakes_are_named() {
	assert mistake(['--kernel', 'k']) == '--arch is required'
	assert mistake(['--arch', 'x86_64']) == '--kernel is required'
	assert mistake(['--arch', 'arm64', '--kernel', 'k']).contains('aarch64 or x86_64')
	assert mistake(['--arch']) == '--arch needs a value'
	assert mistake(['--arch=', '--kernel', 'k']) == '--arch needs a value'
	assert mistake(['--arch', 'x86_64', '--kernel', 'k', '--timeout', '0']).contains('positive')
	assert mistake(['--arch', 'x86_64', '--kernel', 'k', '--timeout', '1m']).contains('positive')
	assert mistake(['--arch', 'x86_64', '--kernel', 'k', '--jobs', '2']) == 'unknown argument: --jobs'
	assert mistake(['devices']) == 'unknown argument: devices'
	assert mistake(['--list=yes']) == '--list takes no value'
}

fn test_the_list_names_what_is_pending() {
	all := list_text(scenarios, '')
	assert all.contains('devices ')
	assert all.contains('aarch64,x86_64  ')
	assert all.contains('ahci ')
	arm := list_text(scenarios, 'aarch64')
	assert !arm.contains('ahci')
	assert arm.contains('qmp-powerdown')
	later := [
		Scenario{
			name:    'later'
			arches:  ['aarch64']
			pending: 'not written yet'
		},
	]
	assert list_text(later, '').contains('(pending: not written yet)')
}

fn test_a_pass_is_one_line_and_what_the_guest_measured() {
	text := report('x86_64', Outcome{
		scenario: 'devices'
		passed:   true
		seconds:  7.26
		notes:    ['MemFree before 1 kB, after 1 kB']
	})
	assert text == 'PASS x86_64 devices (7.3s)\n  MemFree before 1 kB, after 1 kB'
}

fn test_a_failure_says_why_and_shows_the_serial_port() {
	text := report('aarch64', Outcome{
		scenario: 'qmp-powerdown'
		seconds:  39.4
		reason:   'the machine was still running 30 s after {"execute":"system_powerdown"}'
		tail:     ['HWTEST START qmp-powerdown', 'HWTEST STEP waiting for power button']
		state:    '/tmp/s/qmp-powerdown'
	})
	assert text.split_into_lines() == [
		'FAIL aarch64 qmp-powerdown (39.4s)',
		'  the machine was still running 30 s after {"execute":"system_powerdown"}',
		'  last 2 serial lines:',
		'  | HWTEST START qmp-powerdown',
		'  | HWTEST STEP waiting for power button',
		'  logs: /tmp/s/qmp-powerdown',
	]
	silent := report('x86_64', Outcome{
		scenario: 'devices'
		reason:   'timed out after 120 s without "HWTEST START devices"'
		state:    '/tmp/s/devices'
	})
	assert silent.contains('nothing was printed on the serial port')
}
