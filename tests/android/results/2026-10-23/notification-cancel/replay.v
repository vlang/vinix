module main

import os
import json2
import compress.gzip

fn main() {
	dir := os.dir(@FILE)
	out := os.abs_path(if os.args.len > 1 {
		os.args[1]
	} else {
		'build/android-notification-cancel-replay'
	})
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dir + '/sources.json.gz')!)!.bytestr())!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	for mode in ['baseline', 'fixed'] {
		prefix := out + '/' + mode
		os.mkdir_all(prefix + '/src')!
		os.write_file(prefix + '/src/actual_notifications.v', sources[mode + '/actual_notifications.v']!)!
		os.write_file(prefix + '/src/main.v', sources['harness.v']!)!
		build := os.exec([compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none',
			'-o', prefix + '/host', prefix + '/src'])
		assert build.exit_code == 0, build.output
		result := os.exec([prefix + '/host'])
		os.write_file(prefix + '/run.log', result.output)!
		if mode == 'baseline' {
			assert result.exit_code != 0
			assert result.output.contains('cancel must tolerate an absent optional broker')
		} else {
			assert result.exit_code == 0, result.output
			assert result.output.count('NOTIFICATION-HOST PASS ') == 11
			assert result.output.contains('NOTIFICATION-HOST ALL PASS')
		}
		println('NOTIFICATION-CANCEL replay ' + mode + ' PASS')
	}
}
