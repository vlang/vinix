import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt235.json')!)!
	cfg['output'] = b + 'attempt236'
	os.write_file(b + 'attempt236.json', json2.encode(cfg, prettify: true))!
	mut compilers := []&os.Process{}
	for name in ['interact', 'manual', 'run', 'identity'] {
		mut body := os.read_file(b + name + '235.v')!
		body = body.replace('attempt235', 'attempt236')
			.replace('interact235', 'interact236')
			.replace('framework235-accessibility', 'framework236-texture')
			.replace('FRAMEWORK235', 'FRAMEWORK236')
			.replace('framework235', 'framework236')
			.replace('MAPS235', 'MAPS236')
			.replace('identity235', 'identity236')
			.replace('suite235', 'suite236')
		if name == 'run' { body = body.replace('libnative233.so', 'libnative235.so').replace('NATIVE233', 'NATIVE235') }
		os.write_file(b + name + '236.v', body)!
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut args := ['-nocache', '-cc', 'cc']
		if name == 'identity' { args << ['-cflags', '-O2'] }
		args << ['-o', b + name + '236', b + name + '236.v']
		compiler.set_args(args)
		compiler.set_redirect_stdio()
		compiler.run()
		compilers << compiler
	}
	for mut compiler in compilers {
		compiler.wait()
		output := compiler.stdout_slurp() + compiler.stderr_slurp()
		assert compiler.code == 0, output
	}
	println('PREPARE236 PASS framework236 + native235')
}
