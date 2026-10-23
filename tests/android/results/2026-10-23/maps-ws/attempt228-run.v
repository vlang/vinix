import os
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	jar := os.read_bytes(b + 'framework228-outline/api-impl.jar')!
	println('FRAMEWORK228 ' + sha256.sum(jar).hex())
	assert sha256.sum(os.read_bytes(b + 'libnative228.so')!).hex() == '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137'
	os.write_file_array(b + 'native218/api-impl.jar', jar)!
	os.cp(b + 'libnative228.so', b + 'native218/libvinix-android-native.so')!
	mut runner := os.new_process(b + 'suite159')
	runner.set_args([b + 'attempt228.json'])
	runner.set_redirect_stdio()
	runner.run()
	mut input := os.new_process(b + 'interact228')
	input.set_redirect_stdio()
	input.run()
	runner.wait()
	input.wait()
	output := runner.stdout_slurp() + runner.stderr_slurp()
	os.write_file(b + 'attempt228-harness.log', output)!
	print(output)
	interaction := input.stdout_slurp() + input.stderr_slurp()
	os.write_file(b + 'interact228.log', interaction)!
	print(interaction)
	println('INTERACTION-EXIT ' + input.code.str())
	assert runner.code == 0
}
