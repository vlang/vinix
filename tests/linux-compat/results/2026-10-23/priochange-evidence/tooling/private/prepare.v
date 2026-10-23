import os
const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const root = '/Users/alex/code/vinix'
fn renamed(s string) string {
 return s.replace(old, area).replace('prioquery', 'priochange').replace('PRIOQUERY', 'PRIOCHANGE').replace('priority query', 'priority change').replace('Priority query', 'Priority change').replace('6199', '23508')
}
fn main() {
 os.mkdir_all(area + '/frozen-first/priochangefixture')!
 os.mkdir_all(area + '/frozen-first/priochangereferenceinit')!
 os.mkdir_all(area + '/frozen-first/serialcore')!
 os.cp(root + '/tests/linux-compat/priochangefixture/core.v', area + '/frozen-first/priochangefixture/core.v')!
 os.write_file(root + '/tests/linux-compat/priochangereferenceinit/core.v', '') or {
  os.mkdir_all(root + '/tests/linux-compat/priochangereferenceinit')!
 }
 wrapper := renamed(os.read_file(root + '/tests/linux-compat/prioqueryreferenceinit/core.v')!)
 os.write_file(root + '/tests/linux-compat/priochangereferenceinit/core.v', wrapper)!
 os.write_file(area + '/frozen-first/priochangereferenceinit/core.v', wrapper)!
 os.cp(old + '/frozen-second/serialcore/core.v', area + '/frozen-first/serialcore/core.v')!
 for name in ['compile.v', 'native.v', 'reference.v'] { os.write_file(area + '/' + name, renamed(os.read_file(old + '/' + name)!))! }
 os.write_file(root + '/tests/linux-compat/priochange-reference.v', renamed(os.read_file(root + '/tests/linux-compat/prioquery-reference.v')!))!
 // The reference locates its wrapper relative to its frozen source.
 os.mkdir_all(area + '/priochangereferenceinit')!
 os.write_file(area + '/priochangereferenceinit/core.v', wrapper)!
 os.cp(old + '/linux-v6.12-sys.c', area + '/linux-v6.12-sys.c')!
 setup := os.read_file(old + '/setup-kernels.v')!
 stop := setup.index(' source := os.read_file(previous') or { panic('setup anchor') }
 os.write_file(area + '/setup-kernels.v', setup[..stop].replace(old, area).replace('a544610c9', 'ad2c4322b').replace('priority queries', 'priority setters') + " println('Isolated priority setter candidate: ' + commit)\n}\n")!
 println('Prepared isolated fixture and controllers')
}
