// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module policyhost

import fixturehost
import hosttest
import os

fn C.getenv(&char) &char

__global (
	caller_vexe_present bool
	caller_vexe_empty   bool
)

// V3 inserts VEXE before _vinit. Capture two flags before that insertion and
// before the V allocator starts; no pointers or allocated values escape.
@[export: 'vinix_policy_remember_environment'; _constructor]
fn remember_caller_environment() {
	value := C.getenv(c'VEXE')
	caller_vexe_present = value != unsafe { nil }
	caller_vexe_empty = value != unsafe { nil } && unsafe { value[0] == 0 }
}

pub fn environment() map[string]string {
	mut values := os.environ()
	if !caller_vexe_present { values.delete('VEXE') }
	if caller_vexe_empty { values['VEXE'] = '' }
	return values
}

pub fn root() string { return hosttest.root() }

pub fn capture(argv []string) !string {
	if commands_owned() { return owned_capture(argv)! }
	return fixturehost.capture_in_preferred(argv, '', environment(), false, '', false, caller_arch())!
}

pub fn inherited(argv []string) ! {
	if commands_owned() { owned_inherited_environment(argv, environment(), caller_arch(), '')!; return }
	fixturehost.inherited_command_environment_preferred(argv, environment(), caller_arch())!
}

pub fn caller_arch() string {
	$if amd64 {
		return 'amd64'
	} $else {
		return 'arm64'
	}
}

// Preserve the QoS front's VEXE precedence; an explicitly empty compiler is an error.
pub fn run_fixture(work string, vexe bool) ! {
	mut env := environment()
	if vexe && 'VEXE' in env { env['V'] = env['VEXE'] }
	if 'V' in env && env['V'] == '' { return error('Compiler override is empty') }
	compiler := fixturehost.capture_in_preferred(['sh', '-c',
		'. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root()],
		'', env, false, '', false, caller_arch())!
	mut argv := [compiler, '-cc', 'cc', '-enable-globals', '-arch', caller_arch()]
	if os.getenv('VINIX_HOST_POLICY_SANITIZE') == '1' {
		argv << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined']
	}
	argv << ['-o', work + '/fixture', work]
	fixturehost.inherited_command_environment_preferred(argv, env, caller_arch())!
	fixturehost.inherited_command_environment_preferred([work + '/fixture'], env, caller_arch())!
}
