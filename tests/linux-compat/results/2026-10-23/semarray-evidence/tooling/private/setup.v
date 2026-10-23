import os
import net.http

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'
 old := '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'
 root := '/Users/alex/code/vinix'
 os.mkdir_all(area + '/states')!
 os.mkdir_all(area + '/tmp')!
 for name in ['compile.v', 'native.v'] {
  text := os.read_file(old + '/' + name)!.replace(old, area).replace('sempid', 'semarray').replace('SEMPID', 'SEMARRAY')
  os.write_file(area + '/' + name, text)!
 }
 os.mkdir_all(root + '/tests/linux-compat/semarrayreferenceinit')!
 os.write_file(root + '/tests/linux-compat/semarrayreferenceinit/core.v',
  os.read_file(root + '/tests/linux-compat/sempidreferenceinit/core.v')!.replace('sempid', 'semarray').replace('SEMPID', 'SEMARRAY'))!
 response := http.get('https://raw.githubusercontent.com/torvalds/linux/v6.12/ipc/sem.c')!
 assert response.status_code == 200
 os.write_file(area + '/linux-v6.12-sem.c', response.body)!
 println('Prepared array tooling and retained primary reference')
}
