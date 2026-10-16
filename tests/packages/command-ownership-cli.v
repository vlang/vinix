// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import tools.packages.pkglaunch

fn refused(binary string, mode string, source []string, expected string) ! {
	mut process := os.new_process(binary)
	process.set_args([mode, 'app', ...source]); process.set_redirect_stdio_merged(); process.run()
	output := process.stdout_slurp(); process.wait(); code := process.code; process.close()
	if code != 1 || !output.contains(expected) { return error(mode + ': code ' + code.str() + ': ' + output) }
}
fn check() ! {
	if os.args.len != 2 { return error('usage: command-ownership-cli VINIX_PACKAGE') }
	ordinary := os.geteuid() != 0
	isolated := ordinary && pkglaunch.needs_isolation()!
	for mode in ['run-args', 'run-terminal-args']! {
		tty := ordinary && mode == 'run-terminal-args'
		refused(os.args[1], mode, ['--file', '/unused', '--data-cwd', '--data-cwd', '--'], if tty { 'terminal launch requires terminal standard input and output' } else if isolated { 'invalid isolated command launch options' } else { 'command launch repeats --data-cwd' })!
		refused(os.args[1], mode, ['--file', 'relative', '--'], if tty { 'terminal launch requires terminal standard input and output' } else { 'command document must be an absolute printable path' })!
		refused(os.args[1], mode, ['--', 'x'.repeat(4097)], if tty { 'terminal launch requires terminal standard input and output' } else { 'command argument contains NUL or exceeds 4096 bytes' })!
		refused(os.args[1], mode, ['--', ...[]string{len: 16, init: 'x'.repeat(4096)}], if tty { 'terminal launch requires terminal standard input and output' } else { 'command launch exceeds the 64 KiB input limit' })!
		refused(os.args[1], mode, ['--file', 'relative', '--', ...[]string{len: 257, init: ''}], if tty { 'terminal launch requires terminal standard input and output' } else if isolated { 'command launch exceeds the argument/document count limit' } else { 'command launch exceeds the argument count limit' })!
	}
	println('COMMAND CLI run-args/run-terminal-args preserve parser and outer admission diagnostics before session setup PASS')
}
fn main() { check() or { eprintln(err); exit(1) } }
