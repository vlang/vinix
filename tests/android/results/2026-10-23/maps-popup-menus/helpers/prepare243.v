import os
import json2
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	assert !os.exists(b + 'attempt243.json'), 'Maps243 helpers already prepared'
	mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt242.json')!)!
	config['output'] = b + 'attempt243'
	assert config['applications']!.as_array()[0].as_map()['startup_seconds']!.int() == 900
	os.write_file(b + 'attempt243.json', json2.encode(config, prettify: true) + '\n')!
	mut compilers := []&os.Process{}
	for name in ['interact243', 'manual243', 'run243', 'identity243', 'verify-maps243-inputs'] {
		previous := name.replace('243', '242')
		body := os.read_file(b + previous + '.v')!
			.replace('242', '243')
			.replace('framework243-canvas-save', 'framework243-popup-menus')
			.replace('native235', 'native236').replace('NATIVE235', 'NATIVE236')
			.replace('sources111', 'sources112').replace('== 111', '== 112')
			.replace('8e6eb74104871e7b3391a75bd5160c0b74bb1951a45ab9b6626a26e46c965f74', '__FRAMEWORK243_EXPECTED_SHA256__')
			.replace('0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9', '78da0707dc12d4cc8a55e3b3efa3e94ee202ec5c36babbf2470f259423a59d3d')
		os.write_file(b + name + '.v', body)!
		if name == 'verify-maps243-inputs' { continue }
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut arguments := ['-nocache', '-cc', 'cc']
		if name == 'identity243' { arguments << ['-cflags', '-O2'] }
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
	os.write_file(b + 'release242.v', os.read_file(b + 'release241.v')!
		.replace('241', '242').replace('maps-blur-styles', 'maps-canvas-save'))!
	println('PREPARE243 PASS framework243-popup-menus sources112 + native236 sources83; unchanged suite239-stream, max900s; no image or native218 writes; verifier awaits root JAR hash')
}
