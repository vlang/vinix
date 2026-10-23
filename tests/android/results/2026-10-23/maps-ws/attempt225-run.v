import os
import crypto.sha256
fn main() {
 b := 'build/android-maps/'
 jar := os.read_bytes(b+'framework223-autofill/api-impl.jar')!
 assert sha256.sum(jar).hex() == 'ab40d4f8a284c5db5dc819dfa439890ba3805b18a08adbc7c2ed6ccbbc8046a6'
 println('FRAMEWORK223 '+sha256.sum(jar).hex())
 os.write_file_array(b+'native218/api-impl.jar',jar)!
 os.cp(b+'libnative225.so',b+'native218/libvinix-android-native.so')!
 mut runner := os.new_process(b+'suite159')
 runner.set_args([b+'attempt225.json'])
 runner.set_redirect_stdio()
 runner.run()
 mut input := os.new_process(b+'interact225')
 input.set_redirect_stdio()
 input.run()
 runner.wait()
 input.wait()
 output := runner.stdout_slurp()+runner.stderr_slurp()
 os.write_file(b+'attempt225-harness.log',output)!
 print(output)
 interaction := input.stdout_slurp()+input.stderr_slurp()
 os.write_file(b+'interact225.log',interaction)!
 print(interaction)
 println('INTERACTION-EXIT '+input.code.str())
 assert runner.code == 0
}
