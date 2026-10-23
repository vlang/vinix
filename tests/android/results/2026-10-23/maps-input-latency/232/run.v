import os
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	jar := os.read_bytes(b + 'framework228-outline/api-impl.jar')!
	println('FRAMEWORK228 ' + sha256.sum(jar).hex())
	println('NATIVE232 ' + sha256.sum(os.read_bytes(b + 'libnative232.so')!).hex())
	os.write_file_array(b + 'native218/api-impl.jar', jar)!
	os.cp(b + 'libnative232.so', b + 'native218/libvinix-android-native.so')!
	mut runner := os.new_process(b + 'suite159')
	runner.set_args([b + 'attempt232.json'])
	runner.set_redirect_stdio()
	runner.run()
	mut input := os.new_process(b + 'interact232')
	input.set_redirect_stdio()
	input.run()
	runner.wait()
	input.wait()
	output := runner.stdout_slurp() + runner.stderr_slurp()
	os.write_file(b + 'attempt232-harness.log', output)!
	print(output)
	interaction := input.stdout_slurp() + input.stderr_slurp()
	os.write_file(b + 'interact232.log', interaction)!
	print(interaction)
	println('INTERACTION-EXIT ' + input.code.str())
	assert runner.code == 0
}
