import os
import json2

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

fn digest(path string) !string {
 mut f := os.open(path)!
 defer { f.close() }
 mut c := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(&c) == 1
 mut b := []u8{len: 1024 * 1024}
 for {
  n := f.read(mut b) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  assert C.CC_SHA256_Update(&c, b.data, u32(n)) == 1
 }
 mut s := [32]u8{}
 assert C.CC_SHA256_Final(&s[0], &c) == 1
 return s[..].hex()
}

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 saved := area + '/qf-x86-initial-missing-curl'
 assert !os.exists(saved)
 assert os.read_file(area + '/qxo/status')!.trim_space() == '1'
 assert os.read_file(area + '/qf-x86-qxo.status')!.trim_space() == '1'
 raw := os.read_file(area + '/qxo/serial.log')!
 assert raw.contains('PERF-ERROR program="/usr/bin/curl"') && !raw.contains('PERF-DONE')
 os.mkdir_all(saved)!
 mut records := []map[string]string{}
 for line in os.read_lines(area + '/qf-x86-inputs.sha256')! {
  parts := line.split('  ')
  assert parts.len == 2 && digest(parts[1])! == parts[0]
  if parts[1].starts_with(area + '/qf-x86-') {
   target := saved + '/frozen/' + parts[1].all_after(area + '/')
   os.mkdir_all(os.dir(target))!
   os.cp(parts[1], target)!
   assert digest(target)! == parts[0]
   records << {'original': parts[1], 'saved': target, 'sha256': parts[0]}
  }
 }
 for name in ['qf-x86-inputs.sha256', 'qf-x86-tooling.tar.gz', 'qf-x86-archive.log', 'qf-x86-archive.status', 'qf-x86-qxo.log', 'qf-x86-qxo.status'] {
  path := area + '/' + name
  target := saved + '/' + name
  os.mv(path, target)!
  records << {'original': path, 'saved': target, 'sha256': digest(target)!}
 }
 os.mv(area + '/qxo', saved + '/qxo')!
 os.write_file(saved + '/records.json', json2.encode(records, prettify: true) + '\n')!
 os.write_file(saved + '/failure.txt', 'Initial exact Q2 x86 perf attempt: producer and guest harness exit 1. All 36 ops x200 flat and true/sleep x300 churn flat. Cached base userspace omits /usr/bin/curl; exec errno2/status127 stopped remaining churn/cache/desktop before DONE. This attempt is invalid qualification. Full replay requires genuine x86 curl/dependencies, new input pins, unchanged kernel/workload and strict oracle. Original frozen 122-input manifest, source/tool copies, raw logs, receipt and media preserved.\n')!
 println('PASS: initial missing-curl failure, media, 122-input manifest and exact private frozen tools preserved; original state/status1 retained.')
}
