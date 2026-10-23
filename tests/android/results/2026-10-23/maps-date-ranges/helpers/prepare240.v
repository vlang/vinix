import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt240.json'), 'Maps240 helpers already prepared'
	mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt239.json')!)!
	config['output'] = b + 'attempt240'
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 900
	os.write_file(b + 'attempt240.json', json2.encode(config, prettify: true) + '\n')!
	mut compilers := []&os.Process{}
	for name in ['interact240', 'manual240', 'run240', 'identity240', 'verify-maps240-inputs'] {
		previous := name.replace('240', '239')
		body := os.read_file(b + previous + '.v')!
			.replace('attempt239', 'attempt240')
			.replace('interact239', 'interact240')
			.replace('framework239-insets', 'framework240-date-ranges')
			.replace('FRAMEWORK239', 'FRAMEWORK240')
			.replace('MAPS239', 'MAPS240')
			.replace('identity239', 'identity240')
			.replace('sources108', 'sources109')
			.replace('== 108', '== 109')
		os.write_file(b + name + '.v', body)!
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut arguments := ['-nocache', '-cc', 'cc']
		if name == 'identity240' { arguments << ['-cflags', '-O2'] }
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
	println('PREPARE240 PASS framework240-date-ranges + native235; unchanged suite239-stream, max900s; no image or native218 writes')
}
