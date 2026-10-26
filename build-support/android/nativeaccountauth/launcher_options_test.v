// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

fn test_service_launcher_keeps_three_channels_distinct() {
	assert parse_service_options(['--service-fd', '3'])! == ServiceOptions{3, '', -1}
	assert parse_service_options(['--service-fd', '3', '--authenticator-socket', '/broker/account.sock'])! == ServiceOptions{3, '/broker/account.sock', -1}
	assert parse_service_options(['--service-fd', '3', '--ui-fd', '4', '--authenticator-socket', '/broker/account.sock'])! == ServiceOptions{3, '/broker/account.sock', 4}
	assert parse_service_options(['--service-fd', '3', '--authenticator-socket', '/broker/account.sock', '--ui-fd', '2147483647'])!.ui_fd == 2147483647
}

fn test_service_launcher_rejects_forged_or_aliased_descriptors_and_duplicate_options() {
	for arguments in [
		[]string{}, ['--ui-fd', '4'], ['--service-fd'], ['--service-fd', '3', '--ui-fd'],
		['--service-fd', '3', '--ui-fd', '3'], ['--service-fd', '3', '--ui-fd', '4'], ['--service-fd', '3', '--ui-fd', '4', '--ui-fd', '5'],
		['--service-fd', '3', '--authenticator-socket', '/a', '--authenticator-socket', '/b'],
		['--service-fd', '3', '--authenticator-socket', ''], ['--service-fd', '3', '--unknown', '4'],
		['--service-fd', '3', '-l', 'Activity'], ['--service-fd', '3', '--ui-fd', '4', '--ui-fd', '5', '--ui-fd', '6'],
	] {
		parse_service_options(arguments) or { continue }
		panic('accepted invalid service options: ' + arguments.str())
	}
	for value in ['', '-1', '+3', '2', '03', '0000000003', '2147483648', '4294967299', '99999999999', '3x', ' 3', '3\x00'] {
		for arguments in [['--service-fd', value], ['--service-fd', '3', '--authenticator-socket', '/broker/account.sock', '--ui-fd', value]] {
			parse_service_options(arguments) or { continue }
			panic('accepted invalid service descriptor: ' + value)
		}
	}
}
