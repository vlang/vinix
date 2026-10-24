import os
const old = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const root = '/Users/alex/code/vinix'
fn rename(s string) string {return s.replace(old,area).replace('priochange','priozombie').replace('PRIOCHANGE','PRIOZOMBIE').replace('23508','1728').replace('priority change','zombie priority')}
fn main() {
 os.mkdir_all(area + '/states')!
 for dir in ['priozombiefixture','priozombiereferenceinit','serialcore'] {os.mkdir_all(area + '/frozen-first/' + dir)!}
 os.cp(root + '/tests/linux-compat/priozombiefixture/core.v',area + '/frozen-first/priozombiefixture/core.v')!
 wrapper := rename(os.read_file(root + '/tests/linux-compat/priochangereferenceinit/core.v')!)
 os.mkdir_all(root + '/tests/linux-compat/priozombiereferenceinit')!
 os.write_file(root + '/tests/linux-compat/priozombiereferenceinit/core.v',wrapper)!
 os.write_file(area + '/frozen-first/priozombiereferenceinit/core.v',wrapper)!
 os.mkdir_all(area + '/priozombiereferenceinit')!
 os.write_file(area + '/priozombiereferenceinit/core.v',wrapper)!
 os.cp(old + '/frozen-fourth/serialcore/core.v',area + '/frozen-first/serialcore/core.v')!
 for name in ['compile.v','native.v'] {os.write_file(area + '/' + name,rename(os.read_file(old + '/' + name)!))!}
 source := rename(os.read_file(root + '/tests/linux-compat/priochange-reference.v')!)
 os.write_file(root + '/tests/linux-compat/priozombie-reference.v',source)!
 os.write_file(area + '/reference.v',source)!
}
