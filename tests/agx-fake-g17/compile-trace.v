// SPDX-License-Identifier: GPL-2.0-only
import agxhost
import hosttest
import os

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--arch', true, ['amd64', 'arm64']},
	], 1, 'usage: compile-v-trace OUTPUT [--arch {amd64,arm64}]',
		'Generate the allocation-explicit native V AGX tracing core.') or {
		eprintln(err.msg())
		exit(2)
	}
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	arch := if '--arch' in args.options { args.options['--arch'] } else { 'arm64' }
	mut out := agxhost.Transcript{ inherit: true }
	out.generate_trace(root, args.positional[0], arch, os.temp_dir()) or {
		eprintln(err.msg())
		exit(if err.code() != 0 { err.code() } else { 1 })
	}
}
