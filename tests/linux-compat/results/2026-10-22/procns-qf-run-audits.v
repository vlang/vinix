import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
	assert os.args.len == 2
	kind := os.args[1]
	assert kind in ['results', 'drag', 'inputs']
	program := if kind == 'inputs' { area + '/qf2-perf-setup' } else { area + '/qf-verify-perf-' + kind }
	args := if kind == 'inputs' { ['verify'] } else { []string{} }
	log := area + '/qf-perf-' + kind + '-audit.log'
	assert !os.exists(log), 'preserve earlier audits'
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(log, output)!
	os.write_file(area + '/qf-perf-' + kind + '-audit.status', '${code}\n')!
	print(output)
	exit(code)
}
