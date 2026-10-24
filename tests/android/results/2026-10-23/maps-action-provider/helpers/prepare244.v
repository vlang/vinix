import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt244.json'), 'Maps244 helpers already prepared'
	mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt243.json')!)!
	config['output'] = b + 'attempt244'
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 900
	os.write_file(b + 'attempt244.json', json2.encode(config, prettify: true) + '\n')!
	mut compilers := []&os.Process{}
	for name in ['interact244', 'manual244', 'run244', 'identity244', 'verify-maps244-inputs'] {
		previous := name.replace('244', '243')
		body := os.read_file(b + previous + '.v')!
			.replace('243', '244')
			.replace('framework244-popup-menus', 'framework244-action-provider')
			.replace('sources112', 'sources113').replace('== 112', '== 113')
			.replace('0eb5f294900d7ef1683c7444c97ebd59d96d6dc7e2c372731e358ce9c6bde0cc', '__FRAMEWORK244_EXPECTED_SHA256__')
		os.write_file(b + name + '.v', body)!
		if name == 'verify-maps244-inputs' { continue }
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut arguments := ['-nocache', '-cc', 'cc']
		if name == 'identity244' { arguments << ['-cflags', '-O2'] }
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
	os.write_file(b + 'release243.v', os.read_file(b + 'release242.v')!
		.replace('242', '243').replace('maps-canvas-save', 'maps-popup-menus'))!
	println('PREPARE244 PASS framework244-action-provider sources113 + unchanged native236 sources83; suite239-stream, max900s; no image or native218 writes; verifier awaits root JAR hash')
}
