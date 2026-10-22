import os
import json2
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
 assert os.read_file(area + '/qf-perf-drag-desktop.status')!.trim_space() == '0'
 log := os.read_file(area + '/qf-perf-drag-desktop/serial.log')!
 lines := log.split_into_lines().map(it.trim_space())
 assert lines.filter(it == 'VINIX DESKTOP PERF: START').len == 1
 assert lines.filter(it == 'VINIX DESKTOP PERF: DONE').len == 1
 assert !log.contains('PERF-ERROR') && !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
 results := lines.filter(it.starts_with('PERF-RESULT '))
 assert results.len == 1
 assert results[0].contains('variant=new scenario=drag round=1 seconds=5.0 ')
 assert lines.filter(it == 'PERF-DRIVE drag 5').len == 1
 assert lines.filter(it.starts_with('PERF-READY variant=new scenario=drag round=1 after ')).len == 1
 assert lines.filter(it == 'PERF-SHOT variant=new scenario=drag round=1').len == 1
 array := json2.decode[json2.Any](os.read_file(area + '/qf-perf-drag-desktop.json')!)!.as_array()
 assert array.len == 1
 row := array[0].as_map()
 mut fields := map[string]string{}
 for item in results[0].all_after('PERF-RESULT ').fields() {
  key, value := item.all_before('='), item.all_after('=')
  assert key !in fields
  fields[key] = value
  assert row[key]!.str() == value
 }
 assert fields.len == 13 && fields['processes'].int() > 0 && fields['total_mb'].f64() > 0
 before := area + '/qf-perf-drag-shots/before-drag.ppm'
 after := area + '/qf-perf-drag-shots/new-drag-1.ppm'
 mut pins := []string{}
 mut digests := []string{}
 for path in [before, after] {
  bytes := os.read_bytes(path)!
  assert bytes.bytestr().starts_with('P6\n2048 1536\n255\n')
  assert bytes.len == 2048 * 1536 * 3 + 'P6\n2048 1536\n255\n'.len
  hash := sha256.sum(bytes).hex()
  digests << hash
  pins << hash + '  ' + path
  mut p := os.new_process('/usr/bin/sips')
  p.set_args(['-s', 'format', 'png', path, '--out', path.replace('.ppm', '.png')])
  p.run()
  p.wait()
  assert p.code == 0
  p.close()
 }
 assert digests[0] != digests[1], 'before/after screen content must differ'
 os.write_file(area + '/qf-perf-drag-shots.sha256', pins.join('\n') + '\n')!
 println('Queue-fix ARM fresh drag: PASS (one five-second scenario, raw/JSON equal, input marker and distinct full screenshots)')
 println('Screenshot motion requires independent visual review; screen difference alone is not a window-motion assertion.')
}
