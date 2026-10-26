// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

pub struct ServiceOptions {
pub:
	lifetime_fd int
	authenticator_socket string
	ui_fd int = -1
}

fn private_descriptor(value string) !int {
	if value.len == 0 || value.len > 10 || (value.len > 1 && value[0] == `0`) { return error('invalid service descriptor') }
	for byte in value { if byte < `0` || byte > `9` { return error('invalid service descriptor') } }
	number := value.u64()
	if number < 3 || number > 0x7fffffff { return error('invalid service descriptor') }
	return int(number)
}

// Parse only a root-selected service invocation; Activity launches have no
// inherited UI control channel. Each channel has an independent descriptor.
pub fn parse_service_options(arguments []string) !ServiceOptions {
	if arguments.len < 2 || arguments.len > 6 || arguments.len % 2 != 0
		|| arguments[0] != '--service-fd' {
		return error('service host requires --service-fd N [--authenticator-socket ABS] [--ui-fd N]')
	}
	lifetime := private_descriptor(arguments[1])!
	mut authenticator := ''
	mut ui := -1
	for index := 2; index < arguments.len; index += 2 {
		match arguments[index] {
			'--authenticator-socket' {
				if authenticator != '' || arguments[index + 1] == '' {
					return error('duplicate or empty authenticator socket')
				}
				authenticator = arguments[index + 1]
			}
			'--ui-fd' {
				if ui != -1 { return error('duplicate UI control descriptor') }
				ui = private_descriptor(arguments[index + 1])!
				if ui == lifetime { return error('UI and service lifetime channels must be separate') }
			}
			else { return error('unsupported service command channel option') }
		}
	}
	if ui >= 3 && authenticator == '' { return error('UI control requires an authenticator channel') }
	return ServiceOptions{lifetime, authenticator, ui}
}
