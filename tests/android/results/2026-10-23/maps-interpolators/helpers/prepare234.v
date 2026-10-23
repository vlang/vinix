import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt233.json')!)!
	cfg['output'] = b + 'attempt234'
	os.write_file(b + 'attempt234.json', json2.encode(cfg, prettify: true))!
	mut compilers := []&os.Process{}
	for name in ['interact', 'manual', 'run', 'keys', 'zoom'] {
		mut body := os.read_file(b + name + '233.v')!
		body = body.replace('attempt233', 'attempt234').replace('interact233', 'interact234')
		if name == 'run' {
			body = body.replace('framework228-outline', 'framework234-interpolators').replace('FRAMEWORK228', 'FRAMEWORK234')
		}
		os.write_file(b + name + '234.v', body)!
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut args := ['-nocache', '-cc', 'cc']
		if name in ['keys', 'zoom'] { args << ['-path', '@vlib|tests/native-android-run'] }
		args << ['-o', b + name + '234', b + name + '234.v']
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
	println('PREPARE234 PASS (native233 reused; framework234)')
}
