import os
import json2
fn main() {
 b := 'build/android-maps/'
 mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt234.json')!)!
 cfg['output'] = b + 'attempt235'
 os.write_file(b + 'attempt235.json', json2.encode(cfg, prettify: true))!
 mut compilers := []&os.Process{}
 for name in ['interact', 'manual', 'run', 'keys', 'zoom', 'identity'] {
  mut body := os.read_file(b + name + '234.v')!
  body = body.replace('attempt234', 'attempt235').replace('interact234', 'interact235').replace('framework234-interpolators', 'framework235-accessibility').replace('FRAMEWORK234', 'FRAMEWORK235').replace('framework234', 'framework235').replace('MAPS234', 'MAPS235').replace('identity234', 'identity235').replace('suite234', 'suite235')
  os.write_file(b + name + '235.v', body)!
  mut compiler := os.new_process('/Users/alex/code/v/v_old')
  mut args := ['-nocache', '-cc', 'cc']
  if name == 'identity' { args << ['-cflags', '-O2'] }
  if name in ['keys', 'zoom'] { args << ['-path', '@vlib|tests/native-android-run'] }
  args << ['-o', b + name + '235', b + name + '235.v']
  compiler.set_args(args)
  compiler.set_redirect_stdio()
  compiler.run()
  compilers << compiler
 }
 for mut compiler in compilers {
  compiler.wait()
  output := compiler.stdout_slurp() + compiler.stderr_slurp()
  assert compiler.code == 0, output
 }
 println('PREPARE235 PASS (native233 reused; framework235 accessibility)')
}
