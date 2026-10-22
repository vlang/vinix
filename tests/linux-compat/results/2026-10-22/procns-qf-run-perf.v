import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
	assert os.args.len == 3
	kind, scenario := os.args[1], os.args[2]
	assert kind in ['compat', 'drag'] && scenario in ['ops', 'desktop']
	assert kind != 'drag' || scenario == 'desktop'
	label := 'qf-perf-' + kind + '-' + scenario
	log := area + '/' + label + '-producer.log'
	assert !os.exists(log), 'preserve earlier attempts'
	mut process := os.new_process(area + '/qf-desktop-retention-' + kind)
	process.set_args([scenario])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	os.write_file(log, output)!
	os.write_file(log + '.status', '${code}\n')!
	println(label + ': producer exit ' + code.str())
	exit(code)
}
