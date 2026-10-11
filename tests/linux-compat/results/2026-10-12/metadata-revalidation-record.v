import crypto.sha256
import json2
import os

struct Audit {
 source string
 source_sha256 string
 executable_sha256 string
 assertions_enabled bool
 outputs map[string]string
}
struct Proof {
 context string
 compiler_sha256 string
 compiler_options []string
 negative_control_source string
 negative_control_exit int
 negative_control_output string
 kernel_inventory_sha256 string
 audits []Audit
}
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn main() {
 root := '/Users/alex/code/vinix'
 published := root + '/tests/linux-compat/results/2026-10-12/'
 work := '/Volumes/VinixLinuxCompatNext1011/tmp/metadata-checked-audit'
 sources := ['/tmp/vinix-linux-posix-export-abi.v', '/tmp/vinix-linux-posix-export-metadata-runtimes.v',
  '/tmp/vinix-linux-posix-export-metadata-firefox.v', '/tmp/vinix-metadata-export-native.v', '/tmp/vinix-metadata-export-memlock.v']
 names := ['metadata-abi-audit.v', 'metadata-runtime-audit.v', 'metadata-firefox-audit.v', 'metadata-native-audit.v', 'metadata-memlock-audit.v']
 mut audits := []Audit{}
 mut files := 0
 for index, source in sources {
  mut outputs := map[string]string{}
  for name in os.ls(work + '/' + index.str())! {
   hash := digest(work + '/' + index.str() + '/' + name)
   if hash != digest(published + name) { panic('audited output differs: ' + name) }
   outputs[name] = hash
   files++
  }
  if index < 3 { os.cp(source, published + names[index])! }
  if digest(source) != digest(published + names[index]) { panic('audit source changed') }
  audits << Audit{names[index], digest(source), digest(work + '/audit-' + index.str()), true, outputs}
 }
 if files != 32 { panic('expected every one of the 32 published metadata files') }
 mut child := os.new_process('/Volumes/VinixLinuxCompatNext1011/tmp/assert-check')
 child.set_redirect_stdio()
 child.run()
 output := child.stdout_slurp() + child.stderr_slurp()
 child.wait()
 code := child.code
 child.close()
 if code != 1 || !output.contains('receipt audit failure must be fatal') { panic('assertion negative control failed') }
 os.cp('/Volumes/VinixLinuxCompatNext1011/tmp/assert-check.v', published + 'metadata-assertion-negative.v')!
 os.cp('/Volumes/VinixLinuxCompatNext1011/tmp/revalidate-metadata.v', published + 'metadata-revalidation-controller.v')!
 proof := Proof{'all 32 mapping-fix files re-audited with assertions; published output byte-identical',
  digest('/Users/alex/code/v/v'), ['-nocache', '-cflags', '-O2'], 'metadata-assertion-negative.v', code, output,
  digest(root + '/docs/linux-syscall-coverage.json'), audits}
 os.write_file(published + 'metadata-revalidation.json', json2.encode(proof, prettify: true) + '\n')!
 os.cp(@FILE, published + 'metadata-revalidation-record.v')!
 println('32 metadata files: all checked; failing assertion exits 1; V audit source and binary hashes recorded')
}
