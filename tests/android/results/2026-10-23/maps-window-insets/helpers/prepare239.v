import os
import json2
import crypto.sha256

fn main() {
 b := 'build/android-maps/'
 assert !os.exists(b + 'attempt239.json'), 'Maps239 helpers already prepared'
 mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt238.json')!)!
 cfg['output'] = b + 'attempt239'
 os.write_file(b + 'attempt239.json', json2.encode(cfg, prettify: true) + '\n')!
 os.cp(b + 'suite238-stream.v', b + 'suite239-stream.v')!
 mut compilers := []&os.Process{}
 for name in ['suite239-stream', 'interact239', 'manual239', 'run239', 'identity239'] {
  if name != 'suite239-stream' {
   old := name.replace('239', '238')
   body := os.read_file(b + old + '.v')!
    .replace('attempt238', 'attempt239')
    .replace('interact238', 'interact239')
    .replace('framework238-insets', 'framework239-insets')
    .replace('FRAMEWORK238', 'FRAMEWORK239')
    .replace('MAPS238', 'MAPS239')
    .replace('identity238', 'identity239')
    .replace('suite238', 'suite239-stream')
    .replace('suite159', 'suite239-stream')
   os.write_file(b + name + '.v', body)!
  }
  mut compiler := os.new_process('/Users/alex/code/v/v_old')
  mut args := ['-nocache', '-cc', 'cc']
  if name == 'identity239' { args << ['-cflags', '-O2'] }
  if name == 'suite239-stream' { args << ['-path', '@vlib|build-support/android'] }
  args << ['-o', b + name, b + name + '.v']
  compiler.set_args(args)
  compiler.set_redirect_stdio()
  compiler.run()
  compilers << compiler
 }
 for mut compiler in compilers {
  compiler.wait()
  output := compiler.stdout_slurp() + compiler.stderr_slurp()
  os.write_file(b + os.base(compiler.filename) + '-' + os.base(compiler.args[compiler.args.len - 1]) + '-build.log', output)!
  assert compiler.code == 0, output
 }
 prototype := os.exec([b + 'stream238/prototype'])
 os.write_file(b + 'stream238/prototype.log', prototype.output)!
 assert prototype.exit_code == 0, prototype.output
 mut hashes := map[string]string{}
 for name in ['suite159', 'suite-low-disk.v', 'suite239-stream.v', 'suite239-stream', 'prepare239.v', 'run239.v', 'run239', 'manual239.v', 'manual239', 'interact239.v', 'interact239', 'identity239.v', 'identity239', 'attempt239.json', 'stream238/pipeline.v.txt', 'stream238/prototype.v', 'stream238/prototype.v.txt', 'stream238/prototype', 'stream238/prototype.log', 'stream238/prepare.v', 'stream238/suite.diff'] {
  hashes[b + name] = sha256.sum(os.read_bytes(b + name)!).hex()
 }
 os.write_file(b + 'stream238/final-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
 println('PREPARE239 PASS frozen streaming suite, framework239 + native235; no launch or native218 writes')
}
