import os
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	jar := os.read_bytes(b + 'framework243-popup-menus/api-impl.jar')!
	println('FRAMEWORK243 ' + sha256.sum(jar).hex())
	println('NATIVE236 ' + sha256.sum(os.read_bytes(b + 'libnative236.so')!).hex())
	os.write_file_array(b + 'native218/api-impl.jar', jar)!
	os.cp(b + 'libnative236.so', b + 'native218/libvinix-android-native.so')!
	mut runner := os.new_process(b + 'suite239-stream')
	runner.set_args([b + 'attempt243.json'])
	runner.set_redirect_stdio()
	runner.run()
	mut input := os.new_process(b + 'interact243')
	input.set_redirect_stdio()
	input.run()
	runner.wait()
	input.wait()
	output := runner.stdout_slurp() + runner.stderr_slurp()
	os.write_file(b + 'attempt243-harness.log', output)!
	print(output)
	interaction := input.stdout_slurp() + input.stderr_slurp()
	os.write_file(b + 'interact243.log', interaction)!
	print(interaction)
	println('INTERACTION-EXIT ' + input.code.str())
	assert runner.code == 0
}
