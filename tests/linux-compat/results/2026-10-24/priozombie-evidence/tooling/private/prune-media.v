import crypto.sha256
import json2
import os

fn main() {
 area := os.dir(@FILE)
 mut pins := map[string]string{}
 record := area + '/removed-media.json'
 if os.exists(record) { pins = json2.decode[map[string]string](os.read_file(record)!)! }
 for path in os.walk_ext(area + '/states', '') {
  if path.contains('/narm/') || path.contains('/nx86/') || !os.is_file(path) { continue }
  name := os.file_name(path)
  if name.ends_with('.iso') || name.ends_with('.cpio') || name == 'initramfs.tar' || name == 'linux' {
   pins[path] = sha256.sum(os.read_bytes(path)!).hex()
   os.write_file(record, json2.encode(pins, prettify: true) + '\n')!
   os.rm(path)!
  }
 }
 if !os.exists(record) { os.write_file(record, '{}\n')! }
 println('Retained hashes for ' + pins.len.str() + ' removed boot media')
}
