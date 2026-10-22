import os
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

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
 mut results := []string{}
 mut failed := false
 mut seen := map[string]string{}
 for manifest in ['perf-inputs.sha256', 'perf-small-inputs.sha256', 'perf-compat-inputs.sha256', 'perf-frozen-used-inputs.sha256', 'perf-drag-inputs.sha256', 'generated-review-inputs.sha256'] {
  for line in os.read_lines(area + '/' + manifest)! {
   fields := line.split('  ')
   assert fields.len == 2
   expected, path := fields[0], fields[1]
   if path == '/Users/alex/code/vinix/build-support/init-aarch64/initramfs-desktop.tar' {
    results << 'SKIP unused original 6.68GB image: ' + path
    continue
   }
   if path in seen {
    assert seen[path] == expected
    continue
   }
   seen[path] = expected
   actual := digest(path)!
   if actual == expected { results << 'PASS ' + path } else {
    failed = true
    results << 'FAIL ' + path + ' expected=' + expected + ' actual=' + actual
   }
  }
 }
 os.write_file(area + '/perf-post-inputs-check.log', results.join('\n') + '\n')!
 os.write_file(area + '/perf-post-inputs-check.status', if failed {'1\n'} else {'0\n'})!
 if failed { exit(1) }
 println('Used inputs and frozen modules unchanged')
}
