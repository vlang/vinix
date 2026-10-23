import json2
import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	assert '--target=aarch64-linux-musl' in os.args
	mut args := ['-idirafter', '/Users/alex/.cache/vinix-linux-compat/execfd-20261015/sdk/include', '--gcc-install-dir=' + area + '/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0']
	for arg in os.args[1..] {
		if '-c' !in os.args && arg == '-pthread' { continue }
		args << arg
	}
	mut p := os.new_process('clang')
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	index := os.args.index('-o')
	assert index > 0 && index + 1 < os.args.len
	destination := os.args[index + 1]
	assert destination.starts_with('/Users/alex/.cache/vinix-linux-compat/prioquery-20261023/states/')
	os.write_file(destination + '.compiler.json', json2.encode({'compiler': os.find_abs_path_of_executable('clang')!, 'arguments': args.join('\n'), 'status': code.str(), 'output': output}, prettify: true) + '\n')!
	print(output)
	exit(code)
}
