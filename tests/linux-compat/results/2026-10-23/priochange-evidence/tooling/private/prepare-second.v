import json2
import os
const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
fn main() {
 for name in ['priochangefixture', 'serialcore', 'priochangereferenceinit'] {
  os.mkdir_all(area + '/frozen-second/' + name)!
  from := if name == 'priochangefixture' { '/Users/alex/code/vinix/tests/linux-compat/' + name } else { area + '/frozen-first/' + name }
  os.cp(from + '/core.v', area + '/frozen-second/' + name + '/core.v')!
 }
 source := json2.decode[map[string]json2.Any](os.read_file(area + '/prepared-source-inputs.json')!)!
 pins := source['sources']!.as_map()
 build := os.read_file(old + '/build-kernels.v')!.replace(old, area)
  .replace('a544610c9f559e97e86c38dc931c0c8125e174c9', source['base']!.str())
  .replace('730d43fb3d1505c4e7f8ad92c5292586d9c841db', source['commit']!.str())
  .replace('950db21493f4edab4bf9be97407f4f546397ce82e65a6a263e076f5d9aaff8ae', pins['kernel/proc/nice.v']!.str())
  .replace('/semmeta-evidence/', '/prioquery-evidence/')
 os.write_file(area + '/build-kernels.v', build)!
}
