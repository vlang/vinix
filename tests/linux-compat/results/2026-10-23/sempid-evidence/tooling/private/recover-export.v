import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'
const bundle = '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/sempid-evidence'

fn main() {
 assert !os.exists(bundle + '/manifest.json'), 'Only incomplete own export may be removed'
 mut partial := map[string]string{}
 for path in os.walk_ext(bundle, '') {
  if os.is_file(path) { partial[path[bundle.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex() }
 }
 os.write_file(area + '/partial-export-pins.json', json2.encode(partial, prettify: true) + '\n')!
 os.write_file(area + '/states/publish1.recovery.json', json2.encode({
  'export_completed': json2.Any(false),
  'recorder_completed': false,
  'observed_exit_code': 1,
  'observed_error': 'resume-record panicked: failed to open states/publish1.log',
  'free_disk_mib_after_failure': 116,
  'partial_export_pins_sha256': sha256.sum(os.read_bytes(area + '/partial-export-pins.json')!).hex(),
 }, prettify: true) + '\n')!
 os.rmdir_all(bundle)!
 println('Retained incomplete export hashes and recorder failure; removed only own incomplete export')
}
