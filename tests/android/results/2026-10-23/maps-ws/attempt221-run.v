import os
import crypto.sha256
fn main() {
 b := 'build/android-maps/'
 jar := os.read_bytes(b+'framework221-content-capture/api-impl.jar')!
 assert sha256.sum(jar).hex() == 'b68a2228bf00dd24fd01a7da0bc9a66f2026564df4a3f515e15b22cd2b91c75f'
 os.write_file_array(b+'native218/api-impl.jar',jar)!
 os.cp(b+'libnative221.so',b+'native218/libvinix-android-native.so')!
 mut runner := os.new_process(b+'suite159')
 runner.set_args([b+'attempt221.json'])
 runner.set_redirect_stdio()
 runner.run()
 mut input := os.new_process(b+'interact221')
 input.set_redirect_stdio()
 input.run()
 runner.wait()
 input.wait()
 output := runner.stdout_slurp()+runner.stderr_slurp()
 os.write_file(b+'attempt221-harness.log',output)!
 print(output)
 interaction := input.stdout_slurp()+input.stderr_slurp()
 os.write_file(b+'interact221.log',interaction)!
 print(interaction)
 assert runner.code == 0
}
