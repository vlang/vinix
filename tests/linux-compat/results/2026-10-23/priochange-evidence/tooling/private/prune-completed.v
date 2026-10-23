import crypto.sha256
import json2
import os

#include <stdio.h>
fn C.rename(&char, &char) i32

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
 mut removed := json2.decode[map[string]string](os.read_file(area + '/removed-media.json')!)!
 names := ['priochange', 'prioquery', 'threadnice', 'niceabi', 'niceadmit', 'attrnice', 'groupabi', 'grouptid']
 mut count := 0
 for prefix_name in ['m', 'n'] {
 for suffix in ['arm', 'x86'] {
  prefix := area + '/states/' + prefix_name + suffix
  attempt := if prefix_name == 'm' { 'first' } else { 'second' }
  done := os.read_file(area + '/states/maintained-' + attempt + '-' + suffix + '-record.status') or { '' }
  for i, name in names {
   if done.trim_space() != '0' && (i == names.len - 1 || !os.is_dir(prefix + '/' + names[i + 1])) { continue }
   state := prefix + '/' + name
   if !os.is_dir(state) { continue }
   if !os.exists(state + '/serial.log') { continue }
   for path in os.walk_ext(state, '') {
    if !os.is_file(path) || (!path.ends_with('.iso') && !path.ends_with('initramfs.tar') && !path.ends_with('initramfs.cpio') && !path.ends_with('.fd')) { continue }
    removed[path] = sha256.sum(os.read_bytes(path)!).hex()
    os.write_file(area + '/removed-media.next.json', json2.encode(removed, prettify: true) + '\n')!
    next := area + '/removed-media.next.json'
    target := area + '/removed-media.json'
    assert C.rename(next.str, target.str) == 0
    os.rm(path)!
    count++
   }
  }
 }
 }
 println('Pruned completed media with retained SHA-256: ' + count.str())
}
