import os

fn main() {
	b := 'build/android-maps/'
	assert os.exists(b + 'identity245-inputs/preflight.json')
	mut runner := os.new_process(b + 'suite245-resume')
	runner.set_args([b + 'attempt245.json'])
	runner.set_redirect_stdio()
	runner.run()
	mut input := os.new_process(b + 'interact245')
	input.set_redirect_stdio()
	input.run()
	runner.wait()
	input.wait()
	output := runner.stdout_slurp() + runner.stderr_slurp()
	os.write_file(b + 'attempt245-harness.log', output)!
	print(output)
	interaction := input.stdout_slurp() + input.stderr_slurp()
	os.write_file(b + 'interact245.log', interaction)!
	print(interaction)
	println('INTERACTION-EXIT ' + input.code.str())
	assert runner.code == 0
}
