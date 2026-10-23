import os
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	jar := os.read_bytes(b + 'framework227-canvas-z/api-impl.jar')!
	println('FRAMEWORK227 ' + sha256.sum(jar).hex())
	assert sha256.sum(os.read_bytes(b + 'libnative225.so')!).hex() == '592cef0d9d52b9a2795ba78724b6b1b514299511a897996a0d994e7fb56c5f3a'
	os.write_file_array(b + 'native218/api-impl.jar', jar)!
	os.cp(b + 'libnative225.so', b + 'native218/libvinix-android-native.so')!
	mut runner := os.new_process(b + 'suite159')
	runner.set_args([b + 'attempt227.json'])
	runner.set_redirect_stdio()
	runner.run()
	mut input := os.new_process(b + 'interact227')
	input.set_redirect_stdio()
	input.run()
	runner.wait()
	input.wait()
	output := runner.stdout_slurp() + runner.stderr_slurp()
	os.write_file(b + 'attempt227-harness.log', output)!
	print(output)
	interaction := input.stdout_slurp() + input.stderr_slurp()
	os.write_file(b + 'interact227.log', interaction)!
	print(interaction)
	println('INTERACTION-EXIT ' + input.code.str())
	assert runner.code == 0
}
