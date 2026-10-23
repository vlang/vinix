import crypto.sha256
import json2
import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
 mut removed := json2.decode[map[string]string](os.read_file(area + '/removed-media.json')!)!
 names := ['prioquery', 'threadnice', 'niceabi', 'niceadmit', 'attrnice', 'groupabi', 'grouptid']
 mut count := 0
 for pair in [['arm', 'third', 'm3'], ['x86', 'third', 'm3'], ['x86', 'fourth', 'm4']] {
  arch := pair[0]
  state_prefix := area + '/states/' + pair[2] + arch
  finished := os.read_file(area + '/states/maintained-' + pair[1] + '-' + arch + '-record.status') or { '' }
  for index, name in names {
   state := state_prefix + '/' + name
   if finished.trim_space() != '0' && (index == names.len - 1 || !os.is_dir(state_prefix + '/' + names[index + 1])) { continue }
   if !os.is_dir(state) { continue }
   for path in os.walk_ext(state, '') {
    if os.stat(path)!.get_filetype() != .regular { continue }
    if !path.ends_with('.iso') && !path.ends_with('initramfs.tar') && !path.ends_with('initramfs.cpio') && !path.ends_with('.fd') { continue }
    removed[path] = sha256.sum(os.read_bytes(path)!).hex()
    // Persist the hash before unlinking, including if another disk fills.
    os.write_file(area + '/removed-media.json', json2.encode(removed, prettify: true) + '\n')!
    os.rm(path)!
    count++
   }
  }
 }
 println('Pruned completed task boot media with retained SHA-256: ' + count.str())
}
