module main

import os
import json2
import compress.gzip

fn main() {
	dir := os.dir(@FILE)
	out := os.abs_path(if os.args.len > 1 { os.args[1] } else { 'build/android-input-drain-replay' })
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dir + '/sources.json.gz')!)!.bytestr())!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { @VEXE }
	for mode in ['baseline', 'fixed', 'fixed-asan'] {
		prefix := out + '/' + mode
		os.mkdir_all(prefix + '/src')!
		os.write_file(prefix + '/src/actual_input.v', sources[if mode == 'baseline' {
			'baseline/actual_input.v'
		} else {
			'fixed/actual_input.v'
		}]!)!
		os.write_file(prefix + '/src/actual_protocol.v', sources['protocol.v']!)!
		os.write_file(prefix + '/src/main.v', sources['harness.v']!)!
		mut args := [compiler, '-nocache', '-cc', 'cc', '-enable-globals', '-gc', 'none']
		if mode == 'fixed-asan' {
			args << ['-cflags', '-fsanitize=address -fno-omit-frame-pointer', '-ldflags',
				'-fsanitize=address']
			os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true)
		}
		args << ['-o', prefix + '/host', prefix + '/src']
		build := os.exec(args)
		assert build.exit_code == 0, build.output
		result := os.exec([prefix + '/host'])
		os.write_file(prefix + '/run.log', result.output)!
		if mode == 'baseline' {
			assert result.exit_code != 0
			assert result.output.contains("left value: recorded = ['pointer:2:10:20:0']")
		} else {
			assert result.exit_code == 0, result.output
			assert result.output.count('INPUT-HOST PASS ') == 11
			assert result.output.contains('INPUT-HOST ALL PASS')
		}
		println('INPUT-DRAIN replay ' + mode + ' PASS')
	}
}
