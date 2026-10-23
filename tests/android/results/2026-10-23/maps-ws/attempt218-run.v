import os
import crypto.sha256
fn main() {
 b := 'build/android-maps/'
 jar := os.read_bytes(b+'framework217/api-impl.jar')!
 assert sha256.sum(jar).hex() == 'b544bd1b332feb6d7bcb43cbbc7e2ae73498da8eb6626ca4046aa78d89f888ab'
 os.write_file_array(b+'native218/api-impl.jar',jar)!
 mut runner := os.new_process(b+'suite159')
 runner.set_args([b+'attempt218.json'])
 runner.set_redirect_stdio()
 runner.run()
 mut input := os.new_process(b+'interact218')
 input.set_redirect_stdio()
 input.run()
 runner.wait()
 input.wait()
 output := runner.stdout_slurp()+runner.stderr_slurp()
 os.write_file(b+'attempt218-harness.log',output)!
 print(output)
 interaction := input.stdout_slurp()+input.stderr_slurp()
 os.write_file(b+'interact218.log',interaction)!
 print(interaction)
 assert runner.code == 0
}
