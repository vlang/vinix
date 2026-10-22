import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
	assert os.args.len == 2 && os.args[1] in ['pin', 'before']
	phase := os.args[1]
	log := area + '/qf-perf-inputs-' + if phase == 'pin' { 'pin' } else { 'before-audit' } + '.log'
	assert !os.exists(log)
	mut p := os.new_process(area + '/qf2-perf-setup')
	p.set_args([if phase == 'pin' { 'pin' } else { 'verify' }])
	p.set_redirect_stdio_merged()
	p.run()
	out := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, out)!
	os.write_file(log + '.status', '${code}\n')!
	print(out)
	exit(code)
}
