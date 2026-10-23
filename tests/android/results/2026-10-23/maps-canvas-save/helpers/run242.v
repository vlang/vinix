import os
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	jar := os.read_bytes(b + 'framework242-canvas-save/api-impl.jar')!
	println('FRAMEWORK242 ' + sha256.sum(jar).hex())
	println('NATIVE235 ' + sha256.sum(os.read_bytes(b + 'libnative235.so')!).hex())
	os.write_file_array(b + 'native218/api-impl.jar', jar)!
	os.cp(b + 'libnative235.so', b + 'native218/libvinix-android-native.so')!
	mut runner := os.new_process(b + 'suite239-stream')
	runner.set_args([b + 'attempt242.json'])
	runner.set_redirect_stdio()
	runner.run()
	mut input := os.new_process(b + 'interact242')
	input.set_redirect_stdio()
	input.run()
	runner.wait()
	input.wait()
	output := runner.stdout_slurp() + runner.stderr_slurp()
	os.write_file(b + 'attempt242-harness.log', output)!
	print(output)
	interaction := input.stdout_slurp() + input.stderr_slurp()
	os.write_file(b + 'interact242.log', interaction)!
	print(interaction)
	println('INTERACTION-EXIT ' + input.code.str())
	assert runner.code == 0
}
