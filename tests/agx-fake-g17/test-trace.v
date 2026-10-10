// SPDX-License-Identifier: GPL-2.0-only
import agxhost
import hosttest
import os

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--baseline-rev', true, []string{}},
	], 0, 'usage: agx-trace/run [--baseline-rev BASELINE_REV]',
		'Compare native V tracing against frozen C using an independent driver model.') or {
		eprintln(err.msg())
		exit(2)
	}
	baseline := if '--baseline-rev' in args.options {
		args.options['--baseline-rev']
	} else {
		'823aeb116eb3b3ab20463ccb9b1c3fba6f0c41ae'
	}
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	mut out := agxhost.Transcript{ inherit: true }
	out.trace_test(root, baseline, os.temp_dir()) or {
		print(out.stdout)
		eprintln(err.msg())
		exit(if err.code() != 0 { err.code() } else { 1 })
	}
	print(out.stdout)
}
