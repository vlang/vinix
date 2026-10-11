// SPDX-License-Identifier: GPL-2.0-or-later
module hostclipboard
import hosttest
import os
import sourcecommand
pub const maximum = 64 * 1024
pub fn command() ![]string {
	$if macos { return ['/usr/bin/pbpaste', '-Prefer', 'txt'] }
	if os.getenv('WAYLAND_DISPLAY') != '' && os.find_abs_path_of_executable('wl-paste') or { '' } != '' { return ['wl-paste', '--no-newline', '--type', 'text'] }
	if os.getenv('DISPLAY') != '' {
		if os.find_abs_path_of_executable('xclip') or { '' } != '' { return ['xclip', '-selection', 'clipboard', '-out'] }
		if os.find_abs_path_of_executable('xsel') or { '' } != '' { return ['xsel', '--clipboard', '--output'] }
	}
	return error('no host text clipboard available')
}
pub fn read(cancel fn () bool) !string { return read_command(command()!, cancel)! }
// An explicit command is the fixture boundary, never a service environment override.
pub fn read_command(argv []string, cancel fn () bool) !string {
	mut env := os.environ()
	env['LANG'] = 'en_US.UTF-8'; env['LC_ALL'] = 'en_US.UTF-8'
	result := sourcecommand.capture(argv, env, 2, maximum, cancel) or { return error('cannot read host text clipboard: ' + err.msg()) }
	if result.status != 0 { return error('cannot read host text clipboard') }
	hosttest.module_decode_utf8(result.stdout) or { return error('cannot read host text clipboard') }
	return result.stdout
}
