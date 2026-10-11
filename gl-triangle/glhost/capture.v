// SPDX-License-Identifier: GPL-2.0-or-later
module glhost

import fixturehost
import policyhost

fn capture_environment(argv []string, env map[string]string) !string {
	result := fixturehost.capture_owned_bounded(argv, env, policyhost.caller_arch(), '', -1,
		policyhost.command_interrupted, false)!
	if result.status != 0 { return error(result.stderr + result.stdout) }
	return result.stdout
}
