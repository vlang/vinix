import os

fn main() {
	assert os.args.len >= 4
	prefix := os.args[1]
	assert !os.exists(prefix + '.log')
	if os.args[2] == '--preserve-md-failure' {
		os.cp('/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/qf-final-evidence.v', prefix + '.v')!
	}
	offset := if os.args[2] == '--preserve-md-failure' { 3 } else { 2 }
	mut p := os.new_process(os.args[offset])
	p.set_args(os.args[offset + 1..])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(prefix + '.log', output)!
	os.write_file(prefix + '.log.status', code.str() + '\n')!
	print(output)
	exit(code)
}
