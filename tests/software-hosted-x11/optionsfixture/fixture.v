// SPDX-License-Identifier: GPL-2.0-or-later
// Literal operands shared by the real controller, signed child and retainer.
module optionsfixture

pub const scenario = 'launch-options'
pub const app_data = '/home/alex/.local/share/vinix-apps/org.fixture.x11'
pub const document = '/home/alex/granted.txt'
pub const neighbor = '/home/alex/ungranted.txt'
pub const clipboard = '/usr/share/software-hosted-x11-clipboard.txt'
pub const clipboard_url = '/etc/vinix/host-clipboard-url'
pub const input_contents = 'explicit signed file grant λ\n'
pub const output_contents = 'signed child updated explicit grant λ\n'
pub const permission_marker = 'SOFTWARE X11 OPTIONS signed-permission file-grant refused no-child no-lease PASS'
pub const operands_marker = 'SOFTWARE X11 OPTIONS child-observed exact-empty-unicode-metacharacters-flags cwd-private granted-rw neighbor-denied PASS'
pub const bridge_marker = 'SOFTWARE X11 OPTIONS exact-authenticated-package-run-args-vector PASS'
pub const observation_prefix = 'SOFTWARE X11 OPTIONS child-observation '
pub const permission_prefix = 'SOFTWARE X11 OPTIONS permission-observation '
pub const permission_error = 'org.fixture.zznofiles: file permission is not declared'

pub struct Observation {
pub:
	arguments []string
	directory string
	document string
	read string
	written string
	neighbor_denied bool
}

pub struct PermissionObservation {
pub:
	arguments []string
	exit_code int
	output string
	child_marker_found bool
	lease_held bool
	context_found bool
}

pub fn refusal_arguments() []string {
	return ['run', 'alex', '/usr/bin/vinix-package', 'run-args', 'org.fixture.zznofiles',
		'--file', document, '--', '--refusal-child']
}

// Quotes are processed by the existing command_words grammar, never a shell.
pub fn text() string {
	return "'' 'λ;$(literal)' '--file' '--data-cwd' 'a b' '$(touch /tmp/options-shell-ran);*|&<>' '" + document + "'"
}

pub fn arguments() []string {
	return ['--signed-child', '', 'λ;$(literal)', '--file', '--data-cwd', 'a b',
		'$(touch /tmp/options-shell-ran);*|&<>', document]
}

pub fn service_arguments() []string {
	mut result := ['run-args', 'org.fixture.x11', '--data-cwd', '--file', document, '--']
	result << arguments()[1..]
	return result
}

pub fn expected() Observation {
	return Observation{arguments(), app_data, document, input_contents, output_contents, true}
}

pub fn source() string { return $embed_file('fixture.v').to_string() }
