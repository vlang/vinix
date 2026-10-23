import crypto.sha256
import json2
import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 mut removed := map[string]string{}
 for arch in ['arm', 'x86'] {
  directory := area + '/kernel-' + arch + '/kernel/obj'
  for path in os.walk_ext(directory, '.o') {
   removed[path] = sha256.sum(os.read_bytes(path)!).hex()
  }
 }
 os.write_file(area + '/removed-objects.json', json2.encode(removed, prettify: true) + '\n')!
 for path, _ in removed { os.rm(path)! }
 println('Removed owned completed build intermediates: ' + removed.len.str())
}
