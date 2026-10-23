import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt241.json'), 'Maps241 helpers already prepared'
	mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt240.json')!)!
	config['output'] = b + 'attempt241'
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 900
	os.write_file(b + 'attempt241.json', json2.encode(config, prettify: true) + '\n')!
	mut compilers := []&os.Process{}
	for name in ['interact241', 'manual241', 'run241', 'identity241', 'verify-maps241-inputs'] {
		previous := name.replace('241', '240')
		body := os.read_file(b + previous + '.v')!
			.replace('240', '241')
			.replace('framework241-date-ranges', 'framework241-blur-styles')
			.replace('sources109', 'sources110').replace('== 109', '== 110')
			.replace('02aee982892b05c5f950e63d5a5652813386dd48d2532063ba02f90cdf8b75b1', '__FRAMEWORK241_EXPECTED_SHA256__')
		os.write_file(b + name + '.v', body)!
		if name == 'verify-maps241-inputs' { continue }
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut arguments := ['-nocache', '-cc', 'cc']
		if name == 'identity241' { arguments << ['-cflags', '-O2'] }
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
	println('PREPARE241 PASS framework241-blur-styles + native235; unchanged suite239-stream, max900s; no image or native218 writes; verifier awaits root JAR hash')
}
