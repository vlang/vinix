import crypto.sha256
import json2
import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 mut removed := map[string]string{}
 for name in os.ls(area + '/states')! {
  if !os.is_dir(area + '/states/' + name) || name.starts_with('m3') { continue }
  for path in os.walk_ext(area + '/states/' + name, '') {
   if os.stat(path)!.get_filetype() != .regular { continue }
   if path.ends_with('.iso') || path.ends_with('initramfs.tar') || path.ends_with('initramfs.cpio') || path.ends_with('.fd') {
    removed[path] = sha256.sum(os.read_bytes(path)!).hex()
    os.rm(path)!
   }
  }
 }
 os.write_file(area + '/removed-media.json', json2.encode(removed, prettify: true) + '\n')!
 println('Pruned own superseded boot media, with retained SHA-256: ' + removed.len.str())
}
