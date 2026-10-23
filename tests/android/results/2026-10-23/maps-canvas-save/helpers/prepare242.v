import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt242.json'), 'Maps242 helpers already prepared'
	mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt241.json')!)!
	config['output'] = b + 'attempt242'
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 900
	os.write_file(b + 'attempt242.json', json2.encode(config, prettify: true) + '\n')!
	mut compilers := []&os.Process{}
	for name in ['interact242', 'manual242', 'run242', 'identity242', 'verify-maps242-inputs'] {
		previous := name.replace('242', '241')
		body := os.read_file(b + previous + '.v')!
			.replace('241', '242')
			.replace('framework242-blur-styles', 'framework242-canvas-save')
			.replace('sources110', 'sources111').replace('== 110', '== 111')
			.replace('60c171c45dd4a3a2179f6402ce7fdabd72ef3d19ea8596031e58086adc400c04', '__FRAMEWORK242_EXPECTED_SHA256__')
		os.write_file(b + name + '.v', body)!
		if name == 'verify-maps242-inputs' { continue }
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut arguments := ['-nocache', '-cc', 'cc']
		if name == 'identity242' { arguments << ['-cflags', '-O2'] }
		arguments << ['-o', b + name, b + name + '.v']
		compiler.set_args(arguments)
		compiler.set_redirect_stdio()
		compiler.run()
		compilers << compiler
	}
	for mut compiler in compilers {
		compiler.wait()
		output := compiler.stdout_slurp() + compiler.stderr_slurp()
		os.write_file(b + os.base(compiler.filename) + '-' + os.base(compiler.args[compiler.args.len - 1]) + '-build.log', output)!
		assert compiler.code == 0, output
	}
	assert sha256.sum(os.read_bytes(b + 'suite239-stream')!).hex() == 'e99700d9312bb1a95b10d20adc44a8e982e081eeba0aec90f3948fad02bceac6'
	os.write_file(b + 'release241.v', os.read_file(b + 'release240.v')!
		.replace('240', '241').replace('maps-date-ranges', 'maps-blur-styles'))!
	println('PREPARE242 PASS framework242-canvas-save + native235; unchanged suite239-stream, max900s; no image or native218 writes; verifier awaits root JAR hash')
}
