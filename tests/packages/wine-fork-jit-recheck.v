module main

import crypto.sha256
import json2
import os

struct Object {
 path string
 kind string
 target string
 mode u32
 size u64
 digest string
}

struct Capture {
 original_roots []string
 sources map[string]string
 kernel_receipt_digest string
 sealer_digest string
 tar_path string
 tar_digest string
}

fn digest(path string) !string {
 mut f := os.open(path)!
 defer { f.close() }
 mut h := sha256.new()
 defer { unsafe { h.free(); free(h) } }
 mut b := []u8{len: 1024 * 1024}
 defer { unsafe { b.free() } }
 for {
  n := f.read(mut b) or { if err is os.Eof { break } else { return err } }
  if n == 0 { break }
  h.write(b[..n])!
 }
 mut sum := []u8{len: sha256.size}
 defer { unsafe { sum.free() } }
 h.checksum_into(mut sum)
 return sum.hex()
}

fn need(value bool, text string) ! {
 if !value { return error(text) }
}

fn names(root string, prefix string, mut found map[string]bool) ! {
 for name in os.ls(root + if prefix == '' { '' } else { '/' + prefix })! {
  relative := if prefix == '' { name } else { prefix + '/' + name }
  found[relative] = true
  if (os.lstat(root + '/' + relative)!).get_filetype() == .directory {
   names(root, relative, mut found)!
  }
 }
}

fn verify_objects(root string, objects []Object, view bool) !int {
 mut found := map[string]bool{}
 names(root, '', mut found)!
 mut selected := 0
 mut special := 0
 for object in objects {
  ordinary := object.kind in ['regular', 'directory', 'symbolic_link']
  if !ordinary { special++ }
  if view && !ordinary {
   need(object.path !in found, 'special node recreated in view')!
   continue
  }
  selected++
  need(object.path in found, 'missing typed object: ' + root + '/' + object.path)!
  p := root + '/' + object.path
  info := os.lstat(p)!
  need(info.get_filetype().str() == object.kind, 'type differs: ' + p)!
  need(u32(info.get_mode().bitmask()) == object.mode, 'mode differs: ' + p)!
  if object.kind == 'regular' {
   need(info.size == object.size && digest(p)! == object.digest, 'bytes differ: ' + p)!
  } else if object.kind == 'symbolic_link' {
   need(os.readlink(p)! == object.target, 'literal link differs: ' + p)!
  }
 }
 need(selected == found.len, 'extra typed object in ' + root)!
 return special
}

fn run() ! {
 root := '/Users/alex/Library/Caches/vinix-codex/section14/wine-arm-fork-diagnostic-20261026'
 need(digest(root + '.tar.gz')! == '6f724e8c7e838a9b8534ad11a8c08e9c8cec4dffe6e47899168f481ef1ff9f35', 'archive identity')!
 for name, expected in {
  'bundle.sha256': '48a021acf1625ec59528890c1fbea513be8acb7884f16b3295ed329677bbce14'
  'SHA256SUMS': '3032a6c088527a4d34d7e454fbf6564f3d5385ad561fe459afd363334d164aa2'
  'capture.json': '0f45b14fd23e34a54001b2fa982dec7de46dc96e9f6795d315b6dde1d286e087'
 } { need(digest(root + '/' + name)! == expected, 'metadata identity: ' + name)! }
 capture := json2.decode[Capture](os.read_file(root + '/capture.json')!)!
 need(capture.original_roots.len == 2, 'original roots')!
 mut special := 0
 mut typed := 0
 for index, name in ['raw', 'tools'] {
  objects := json2.decode[[]Object](os.read_file(root + '/' + name + '-objects.json')!)!
  typed += objects.len
  special += verify_objects(capture.original_roots[index], objects, false)!
  verify_objects(root + '/' + name, objects, true)!
 }
 mut regular := 0
 for line in os.read_lines(root + '/SHA256SUMS')! {
  need(line.len > 66 && line[64..66] == '  ', 'SHA256SUMS syntax')!
  need(digest(root + '/' + line[66..])! == line[..64], 'SHA256SUMS file differs')!
  regular++
 }
 for source, hash in capture.sources { need(digest(root + '/sources/' + source)! == hash, 'captured source differs')! }
 need(digest(root + '/kernel-receipt.json')! == capture.kernel_receipt_digest, 'kernel receipt bytes')!
 need(digest(root + '/sealer')! == capture.sealer_digest, 'sealer bytes')!
 need(digest(capture.tar_path)! == capture.tar_digest, 'tar bytes')!
 need(typed == 150 && special == 1, 'typed counts')!
 // The original independent verifier's checks remain unchanged. Only its
 // report destination is adapted, so both fresh rechecks preserve old evidence.
 need(os.args.len == 2, 'usage: wine-fork-jit-recheck NEW_RECHECK_REPORT.json')!
 out := os.args[1]
 need(out in [
  '/Users/alex/Library/Caches/vinix-codex/section14/wine-arm-fork-reclamation-01/original-before.json',
  '/Users/alex/Library/Caches/vinix-codex/section14/wine-arm-fork-reclamation-01/original-after.json',
 ], 'report is outside exact reclamation receipt paths')!
 need(!os.exists(out), 'review output exists')!
 os.write_file(out, json2.encode({
  'result': 'PASS'
  'scope': 'Independent raw/view typed correspondence and SHA256SUMS byte hashes; separate maintained streaming archive checker validates archive payload and gzip integrity. Failed diagnostics only.'
  'reviewer_source_sha256': digest(@FILE)!
  'reviewer_binary_sha256': digest(os.executable())!
  'archive_sha256': digest(root + '.tar.gz')!
  'bundle_sha256': digest(root + '/bundle.sha256')!
  'typed_objects': typed.str()
  'special_objects_metadata_only': special.str()
  'sha256sums_regular_files': regular.str()
 }) + '\n')!
 println('PASS typed_objects=' + typed.str() + ' special_metadata_only=' + special.str() + ' SHA256SUMS_files=' + regular.str())
 println('review_sha256=' + digest(out)!)
}

fn main() { run() or { eprintln(err); exit(1) } }
