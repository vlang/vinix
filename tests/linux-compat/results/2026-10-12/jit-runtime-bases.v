import crypto.sha256
import json2
import os
fn main() {
 output := '/tmp/vinix-linux-jit-1012'
 assert !os.exists(output)
 for arch in ['aarch64', 'x86_64'] {
  source := if arch == 'aarch64' { '/Users/alex/code/vinix/build-aarch64-userland/staging' }
   else { '/Volumes/VinixLinuxCompatContinue1011/native-runtime-inputs3-x86/root' }
  base := output + '/base-' + arch
  for path in ['bin', 'sbin', 'lib', 'etc', 'root', 'tmp', 'dev', 'proc', 'sys', 'usr/bin'] { os.mkdir_all(base + '/' + path)! }
  mut hashes := map[string]string{}
  for path in ['bin/busybox', 'lib/ld-musl-' + arch + '.so.1'] {
   bytes := os.read_bytes(source + '/' + path)!
   assert bytes.len > 100000 && bytes[..4] == [u8(127), `E`, `L`, `F`]
   assert int(bytes[18]) + (int(bytes[19]) << 8) == if arch == 'aarch64' { 183 } else { 62 }
   os.write_file_array(base + '/' + path, bytes)!
   os.chmod(base + '/' + path, 0o755)!
   hashes[path] = sha256.sum(bytes).hex()
  }
  os.cp(base + '/lib/ld-musl-' + arch + '.so.1', base + '/lib/libc.musl-' + arch + '.so.1')!
  os.symlink('busybox', base + '/bin/sh')!
  os.write_file(base + '/etc/passwd', 'root:x:0:0:root:/root:/bin/sh\ncompat:x:1000:1000:compat:/home/compat:/bin/sh\n')!
  os.write_file(base + '/etc/group', 'root:x:0:\ncompat:x:1000:\n')!
  os.write_file(output + '/base-' + arch + '.json', json2.encode(hashes, prettify: true) + '\n')!
 }
}
