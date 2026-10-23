import os
import crypto.sha256
fn main() {
 b := 'build/android-maps/'
 jar := os.read_bytes(b+'framework217-observer2/api-impl.jar')!
 assert sha256.sum(jar).hex() == 'acd7c4ca1ab2447f528879b2ecc8533d38129627f50e867cc8a586b557978593'
 os.write_file_array(b+'native218/api-impl.jar',jar)!
 os.cp(b+'libnative219.so',b+'native218/libvinix-android-native.so')!
 mut runner := os.new_process(b+'suite159')
 runner.set_args([b+'attempt219.json'])
 runner.set_redirect_stdio()
 runner.run()
 mut input := os.new_process(b+'interact219')
 input.set_redirect_stdio()
 input.run()
 runner.wait()
 input.wait()
 output := runner.stdout_slurp()+runner.stderr_slurp()
 os.write_file(b+'attempt219-harness.log',output)!
 print(output)
 interaction := input.stdout_slurp()+input.stderr_slurp()
 os.write_file(b+'interact219.log',interaction)!
 print(interaction)
 assert runner.code == 0
}
