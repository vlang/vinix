import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt232.json')!)!
	cfg['output'] = b + 'attempt233'
	os.write_file(b + 'attempt233.json', json2.encode(cfg, prettify: true))!
	mut compilers := []&os.Process{}
	for name in ['interact', 'manual', 'run', 'keys', 'zoom'] {
		mut body := os.read_file(b + name + '232.v')!.replace('232', '233')
		if name == 'interact' { body = body.replace('0 .. 260', '0 .. 400') }
		if name == 'manual' {
			body = body.replace('0 .. 100', '0 .. 200')
			body = body.replace("for _ in 0 .. 200 {", "for _ in 0 .. 200 {\n\t\t\tlog := os.read_file(path + 'serial.log') or { '' }\n\t\t\tassert !log.contains('APK-SUITE-EXIT id='), 'Maps exited before map presentation'")
		}
		os.write_file(b + name + '233.v', body)!
		mut compiler := os.new_process('/Users/alex/code/v/v_old')
		mut args := ['-nocache', '-cc', 'cc']
		if name in ['keys', 'zoom'] { args << ['-path', '@vlib|tests/native-android-run'] }
		args << ['-o', b + name + '233', b + name + '233.v']
		compiler.set_args(args)
		compiler.set_redirect_stdio()
		compiler.run()
		compilers << compiler
	}
	for mut compiler in compilers {
		compiler.wait()
		output := compiler.stdout_slurp() + compiler.stderr_slurp()
		if compiler.code != 0 { print(output) }
		assert compiler.code == 0, output
	}
	println('PREPARE233 PASS')
}
