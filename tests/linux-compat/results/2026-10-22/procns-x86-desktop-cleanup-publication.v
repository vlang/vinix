import json2
import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 records := json2.decode[[]map[string]json2.Any](os.read_file(area + '/desktop-scratch-cleanup-records.json')!)!
 assert records.len == 2
 for item in records { assert !os.exists(item['path']!.str()) }
 assert os.is_file(area + '/du/vm/test.iso') && os.is_file(area + '/dt/vm/test.iso')
 log := os.read_file(area + '/desktop-scratch-cleanup.log')!
 assert log.count('Removed hashed scratch ISO ') == 2
 os.write_file(area + '/desktop-scratch-cleanup.status', '0\n')!
 mut disk := os.new_process('/bin/df')
 disk.set_args(['-k', area])
 disk.set_redirect_stdio_merged()
 disk.run()
 output := disk.stdout_slurp()
 disk.wait()
 assert disk.code == 0
 disk.close()
 os.write_file(area + '/desktop-scratch-cleanup-after.txt', output)!
 mut publication := json2.decode[map[string]string](os.read_file(area + '/desktop-publication-inputs.json')!)!
 for name in ['desktop-dedup.v', 'desktop-dedup-records.json', 'desktop-dedup-final.log', 'desktop-dedup.log', 'desktop-dedup-before.txt', 'desktop-dedup-after.txt', 'desktop-scratch-cleanup.v', 'desktop-scratch-cleanup-records.json', 'desktop-scratch-cleanup.log', 'desktop-scratch-cleanup.status', 'desktop-scratch-cleanup-after.txt', 'desktop-cleanup-publication.v'] {
  path := area + '/' + name
  assert os.is_file(path)
  publication['x86-' + name] = path
 }
 os.write_file(area + '/desktop-publication-inputs.json', json2.encode(publication, prettify: true) + '\n')!
 println('Historical desktop publication now includes exact-byte dedup records and two hash-checked scratch ISO removals. du/dt exact ISO, all archives, kernels, receipts and raw evidence retained.')
 print(output)
}
