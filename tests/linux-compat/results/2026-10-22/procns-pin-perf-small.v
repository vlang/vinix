import os
import crypto.sha256
fn digest(path string) !string {
 mut f := os.open(path)!
 defer { f.close() }
 mut d := sha256.new()
 mut b := []u8{len: 1024 * 1024}
 for {
  n := f.read(mut b) or { break }
  if n == 0 { break }
  d.write(b[..n])!
 }
 return d.sum([]u8{}).hex()
}
fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 mut pins := []string{}
 for path in ['/Users/alex/code/vinix/logs/m1-gpu-deploy-20261018/build-support/init-aarch64/initramfs-desktop.tar', area + '/frozen-perf/desktop-retention-small.v', area + '/desktop-retention-frozen', area + '/arm-track/kernel/bin/vinix', '/Users/alex/code/vinix/logs/desktop-ram-fix/vinix-desktop-arm64'] {
  pins << digest(path)! + '  ' + path
 }
 os.write_file(area + '/perf-small-inputs.sha256', pins.join('\n') + '\n')!
 println('Small cached image and driver inputs pinned')
}
