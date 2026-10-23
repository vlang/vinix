import crypto.sha256
import json2
import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/semword-20261023'
 bundle := '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/semword-evidence'
 object := json2.decode[map[string]json2.Any](os.read_file(bundle + '/manifest.json')!)!
 omitted := object['omitted'] or { panic('Missing omitted media pins') }
 pins := json2.decode[map[string]string](json2.encode(omitted))!
 mut removed := map[string]string{}
 mut bytes := i64(0)
 for path, pin in pins {
  if !(path.starts_with(area + '/states/') ||
   path.starts_with('/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/states/sw1-')) { continue }
  if !(path.ends_with('.iso') || path.ends_with('/initramfs.tar') || path.ends_with('/initramfs.cpio')) { continue }
  if !os.is_file(path) { continue }
  assert sha256.sum(os.read_bytes(path)!).hex() == pin
  bytes += i64(os.file_size(path))
  os.rm(path)!
  removed[path] = pin
 }
 os.write_file(area + '/removed-media-pins.json', json2.encode(removed, prettify: true) + '\n')!
 println('Removed only verified, explicitly omitted task media: ' + removed.len.str() + ' files; ' + bytes.str() + ' bytes')
}
