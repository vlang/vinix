import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'

fn digest(path string) !string {
 expected := os.file_size(path)
 mut f := os.open(path)!
 defer { f.close() }
 mut d := sha256.new()
 mut b := []u8{len: 1024 * 1024}
 mut total := u64(0)
 for {
  n := f.read(mut b) or { break }
  if n == 0 { break }
  total += u64(n)
  d.write(b[..n])!
 }
 if total != expected || os.file_size(path) != expected { return error('Incomplete or unstable input: ' + path) }
 return d.sum([]u8{}).hex()
}

fn main() {
 mut paths := []string{}
 for group in ['frozen-perf', 'frozen-perf-compat'] {
  for path in os.walk_ext(area + '/' + group, '.v') { paths << path }
  for path in os.walk_ext(area + '/' + group, '.h') { paths << path }
  paths << area + '/' + group + '/measure.c'
  paths << area + '/' + group + '/perf-init.sh'
 }
 paths << [root + '/boot-image/edk2-aarch64-code-2048x1536.fd', root + '/scripts/run-aarch64.sh', root + '/build-support/qemu-storage.sh', root + '/tools/build-qemu-module-iso', root + '/tools/build-qemu-module-iso.v', '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v', area + '/desktop-retention-frozen', area + '/desktop-retention-compat']
 paths.sort()
 mut pins := []string{}
 for path in paths { pins << digest(path)! + '  ' + path }
 os.write_file(area + '/perf-frozen-used-inputs.sha256', pins.join('\n') + '\n')!
 println('Pinned used frozen inputs: ' + pins.len.str())
}
