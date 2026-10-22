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
 saved := area + '/qf-x86-audit-json-correction'
 assert !os.exists(saved)
 os.mkdir_all(saved)!
 mut records := []map[string]string{}
 for name in ['qf-x86-audit-tail.v', 'qf-x86-audit.v', 'qf-x86-audit', 'qf-x86-inputs.sha256', 'qf-x86-tooling.tar.gz', 'qf-x86-archive.log', 'qf-x86-archive.status'] {
  source, target := area + '/' + name, saved + '/' + name
  hash := digest(source)!
  os.cp(source, target)!
  assert digest(target)! == hash
  records << {'original': source, 'saved': target, 'sha256': hash}
 }
 for name in ['qf-x86-inputs.sha256', 'qf-x86-tooling.tar.gz', 'qf-x86-archive.log', 'qf-x86-archive.status'] { os.rm(area + '/' + name)! }
 path := area + '/qf-x86-audit-tail.v'
 before := os.read_file(path)!
 old := "array := json2.decode[json2.Any](os.read_file(work + '/results.json')!)!.as_array()"
 new := old + ".filter('report' !in it.as_map())"
 assert before.count(old) == 1
 os.write_file(path, before.replace(old, new))!
 os.write_file(saved + '/records.json', json2.encode(records, prettify: true) + '\n')!
 os.write_file(saved + '/notes.txt', 'Audit-only correction before its first full invocation: combined qxo JSON contains structured ops/churn/cache reports as well as desktop rows. Select rows without report when checking the exact two idle/apps desktop rows. All strict raw ops/churn/cache checks and raw/JSON desktop equality remain. Guest inputs, wrapper, kernel, init, userspace and workload remain byte-identical to launch; old142-input manifest/auditor/tooling preserved here and new142-input manifest repins the corrected audit.\n')!
 println('PASS: audit-only JSON desktop selection corrected; prior142manifest/auditor/tooling preserved; no guest input changed.')
}
