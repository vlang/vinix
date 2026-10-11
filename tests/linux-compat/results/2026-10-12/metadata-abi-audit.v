import crypto.sha256
import json2
import os
import strconv

fn main() {
 assert os.args.len == 8
 fixture := os.args[1]
 tag := os.args[2]
 before := os.args[3]
 after := os.args[4]
 count := strconv.atoi(os.args[5])!
 area := (os.getenv_opt('VINIX_ABI_AREA') or { '/Volumes/VinixLinuxCompatContinue1011' }) + '/'
 root := '/Users/alex/code/vinix/'
 date := os.getenv_opt('VINIX_ABI_DATE') or { '2026-10-11' }
 assert date in ['2026-10-11', '2026-10-12']
 out := root + 'tests/linux-compat/results/' + date + '/'
 os.mkdir_all(out)!
 for arch, directory in {'aarch64': 'arm', 'x86_64': 'x86'} {
  mut source_hash := ''
  for phase in ['before', 'after'] {
   state := area + if phase == 'before' { before } else { after } + directory
   raw := os.read_file(state + '/receipt.json')!
   receipt := json2.decode[json2.Any](raw)!.as_map()
   assert receipt['architecture']!.str() == arch
   assert receipt['context']!.str() == 'QEMU guest; native musl ELF64'
   assert receipt['kernel_sha256']!.str() == sha256.sum(os.read_bytes(state + '/kernel/bin/vinix')!).hex()
   rows := receipt['results']!.as_array()
   assert rows.len == if phase == 'before' { 1 } else { count }
   mut names := map[string]bool{}
   for result in rows {
    item := result.as_map()
    name := item['name']!.str()
    assert name !in names
    names[name] = true
    assert item['source_sha256']!.str() == sha256.sum(os.read_bytes(root + 'tests/linux-compat/' + name + 'fixture/core.v')!).hex()
    assert item['init_sha256']!.str() == sha256.sum(os.read_bytes(state + '/' + name + '/init')!).hex()
    assert item['iso_sha256']!.str() == sha256.sum(os.read_bytes(state + '/' + name + '/test.iso')!).hex()
    assert item['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
    if name == fixture {
     if phase == 'before' { source_hash = item['source_sha256']!.str() }
     else { assert item['source_sha256']!.str() == source_hash }
    }
   }
   assert names[fixture]
   log := os.read_file(state + '.log')!
   assert log.contains(if phase == 'before' { os.args[6] } else { os.args[7] })
   name := tag + '-' + phase + '-' + arch
   assert !os.exists(out + name + '.json') && !os.exists(out + name + '.log')
   os.write_file(out + name + '.json', raw)!
   os.write_file(out + name + '.log', log)!
   println(name + ': matching source and actual guest verdicts verified')
  }
 }
}
