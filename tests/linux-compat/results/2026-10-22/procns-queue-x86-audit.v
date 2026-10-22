// Compile without -prod: subprocess controls ensure assertions execute.
import os
import json2

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn natural(value string) u64 {
 assert value != '' && value.bytes().all(it.is_digit()), 'invalid natural: ' + value
 return value.u64()
}

fn decimal(value string) f64 {
 assert value != '' && value.count('.') <= 1 && value.replace('.', '') != '' && value.replace('.', '').bytes().all(it.is_digit()), 'invalid decimal: ' + value
 return value.f64()
}

fn lines(log string, prefix string) []string {
 return log.split_into_lines().map(it.trim_space()).filter(it.starts_with(prefix))
}

fn fields(text string) map[string]string {
 mut result := map[string]string{}
 for field in text.fields() {
  assert field.contains('=')
  key, value := field.all_before('='), field.all_after('=')
  assert key != '' && key !in result && value != ''
  result[key] = value
 }
 return result
}

fn label(row map[string]string, scenario string) {
 assert row['variant'] == 'new' && row['scenario'] == scenario && row['round'] == '1'
}

fn finished(log string) {
 assert lines(log, 'VINIX DESKTOP PERF: START').len == 1
 assert lines(log, 'VINIX DESKTOP PERF: DONE').len == 1
 assert lines(log, 'PERF-ERROR').len == 0
 lower := log.to_lower()
 assert !lower.contains('kernel panic') && !lower.contains('fatal exception')
}

fn verify_ops(log string) {
 assert log.contains('PERF-ROOT device=') && log.contains(' target=/root type=ext2') && log.split_into_lines().any(it.contains(' /root ext2 ')), 'x86 ext2 /root mount required for filesystem operations'
 rows := lines(log, 'PERF-OPS ')
 assert rows.len == 36, '36 ops rows required'
 mut expected := map[string]bool{}
 for name in ['stat', 'pipe', 'socketpair', 'inet_socket', 'eventfd', 'epoll', 'timerfd', 'poll', 'proc_read', 'proc_list', 'readdir', 'dup', 'mmap', 'thread', 'signal', 'fault', 'fork', 'memfd'] {
  expected[name + '/tmp'] = true
 }
 for directory in ['/tmp', '/root'] {
  for name in ['file', 'rename', 'unlink_open', 'rename_over', 'hardlink', 'mkdir', 'symlink', 'unix_connect', 'unix_datagram'] { expected[name + directory] = true }
 }
 for line in rows {
  row := fields(line.all_after('PERF-OPS '))
  assert row.len == 7, 'unexpected ops fields or slab deltas: ' + line
  label(row, 'ops')
  assert row['count'] == '200' && row['bytes_per_op'] == '0', line
  key := row['op'] + row['dir']
  assert key in expected, 'duplicate or unexpected op: ' + line
  expected.delete(key)
 }
 assert expected.len == 0
}

fn verify_churn(log string) {
 rows := lines(log, 'PERF-CHURN ')
 assert rows.len == 4
 mut expected := {
  '/bin/true': true
  '/bin/sleep 0': true
  '/usr/bin/curl --version': true
  '/bin/busybox awk BEGIN{}': true
 }
 for line in rows {
  assert line.count('program="') == 1 && line.count('"') == 2
  program := line.all_after('program="').all_before('"')
  assert program in expected, line
  expected.delete(program)
  row := fields(line.all_after('PERF-CHURN ').all_before('program="') + line.all_after('program="').all_after('"'))
  assert row.len == 6
  label(row, 'churn')
  assert row['runs'] == '300' && row['retained_kb'] == '0' && row['per_run_bytes'] == '0', line
 }
 assert expected.len == 0
 // The producer emits PERF-SLAB only for nonzero object/page changes.
 assert lines(log, 'PERF-SLAB ').len == 0, 'nonzero churn slab deltas'
}

fn verify_cache(log string) {
 rows := lines(log, 'PERF-CACHE ')
 assert rows.len == 1
 row := fields(rows[0].all_after('PERF-CACHE '))
 assert row.len == 7
 label(row, 'cache')
 assert row['written_mb'] == '32'
 // Declared before the cache scenario completed: permit data and metadata
 // cache retention within twice the 32MiB workload, rather than call it zero.
 assert natural(row['used_mb']) <= 64
 assert natural(row['cached_kb']) <= 65536
 natural(row['slab_kb'])
 mut seen := map[string]bool{}
 for line in lines(log, 'PERF-MEMINFO variant=new scenario=cache round=1 ') {
  for key in ['Cached:', 'Slab:'] {
   if !line.contains(' ' + key) { continue }
   assert key !in seen
   seen[key] = true
   tail := line.all_after(key).fields()
   assert tail.len == 2 && tail[1] == 'kB'
   expected := if key == 'Cached:' { row['cached_kb'] } else { row['slab_kb'] }
   if key == 'Cached:' { assert natural(tail[0]) == natural(expected) } else {
    // awk and sed are separate forked probes; allow up to 1MiB of
    // temporary heap pages between their adjacent snapshots.
    left, right := natural(tail[0]), natural(expected)
    assert if left > right { left - right <= 1024 } else { right - left <= 1024 }
   }
  }
 }
 assert seen.len == 2
}

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) int
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) int
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) int

fn digest(path string) !string {
 mut input := os.open(path)!
 defer { input.close() }
 mut context := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(&context) == 1
 mut buffer := []u8{len: 1024 * 1024}
 mut total := u64(0)
 for {
  n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  total += u64(n)
  assert C.CC_SHA256_Update(&context, buffer.data, u32(n)) == 1
 }
 assert total == os.file_size(path)
 mut sum := [32]u8{}
 assert C.CC_SHA256_Final(&sum[0], &context) == 1
 return sum[..].hex()
}

struct Position { x int y int }

fn png(path string) !string {
 target := path.replace('.ppm', '.png')
 mut process := os.new_process('/usr/bin/sips')
 process.set_args(['-s', 'format', 'png', path, '--out', target])
 process.set_redirect_stdio_merged()
 process.run()
 output := process.stdout_slurp()
 process.wait()
 status := process.code
 process.close()
 assert status == 0, output
 return target
}

fn window_position(path string) !Position {
 data := os.read_bytes(path)!
 header := 'P6\n2048 1536\n255\n'
 assert data.len == header.len + 2048 * 1536 * 3 && data[..header.len].bytestr() == header
 for y in 25 .. 1450 {
  mut run := 0
  for x in 20 .. 2000 {
   at := header.len + (y * 2048 + x) * 3
   r, g, b := int(data[at]), int(data[at+1]), int(data[at+2])
   if r > 220 && g > 220 && b > 220 && r - g > -15 && r - g < 15 && r - b > -15 && r - b < 15 {
    run++
    if run == 300 { return Position{x - 299, y} }
   } else { run = 0 }
  }
 }
 return error('System window top border not found')
}

fn desktop(log string, work string, expected []string) ! {
 array := json2.decode[json2.Any](os.read_file(work + '/results.json')!)!.as_array().filter('report' !in it.as_map())
 assert array.len == expected.len
 results := lines(log, 'PERF-RESULT ')
 assert results.len == expected.len
 mut seen := map[string]bool{}
 for line in results {
  row := fields(line.all_after('PERF-RESULT '))
  scenario := row['scenario']
  assert scenario in expected && scenario !in seen
  seen[scenario] = true
  label(row, scenario)
  assert row.len == 13 && decimal(row['seconds']) >= 5 && decimal(row['seconds']) <= 120
  count := natural(row['processes'])
  assert count > 0 && decimal(row['total_mb']) > 0 && decimal(row['physical_mb']) > 0
  for key in ['desktop_cpu', 'apps_cpu', 'total_cpu', 'desktop_mb', 'apps_mb', 'total_mb', 'system_used_mb', 'physical_mb'] { assert decimal(row[key]) <= 16384 }
  prefix := 'variant=new scenario=' + scenario + ' round=1'
  ready := lines(log, 'PERF-READY ' + prefix + ' after ')
  assert ready.len == 1 && natural(ready[0].all_after(' after ').all_before('s')) <= 120
  assert lines(log, 'PERF-SHOT ' + prefix).len == 1
  procs := lines(log, 'PERF-PROC ' + prefix + ' ')
  assert procs.len == int(count)
  mut pids := map[u64]bool{}
  for process in procs {
   data := fields(process.all_after('PERF-PROC '))
   pid := natural(data['pid'])
   assert pid > 0 && pid !in pids
   pids[pid] = true
  }
  if scenario == 'apps' {
   for name in ['vinix-activity', 'vinix-terminal', 'vinix-calculator', 'vinix-clock'] { assert procs.any(it.contains('/usr/bin/' + name + '[')), 'missing app: ' + name }
  }
  matching := array.filter(it.as_map()['scenario']!.str() == scenario)
  assert matching.len == 1
  json_row := matching[0].as_map()
  for key, value in row { assert json_row[key]!.str() == value, 'JSON/raw mismatch ' + key }
 }
 assert lines(log, 'PERF-READY ').len == expected.len && lines(log, 'PERF-SHOT ').len == expected.len
}

fn control(option string, marker string) {
 mut child := os.new_process(os.executable())
 child.set_args([option])
 child.set_redirect_stdio_merged()
 child.run()
 output := child.stdout_slurp()
 child.wait()
 status := child.code
 child.close()
 assert status == 1 && output.contains(marker), 'negative control did not reject: ' + output
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--assertion-control' { assert false, 'x86 forced assertion control'; return }
 if os.args.len == 2 && os.args[1] == '--missing-ops-control' { verify_ops('PERF-ROOT device=/dev/sd0 target=/root type=ext2\n/dev/sd0 /root ext2 rw 0 0\n'); return }
 assert os.args.len == 1
 control('--assertion-control', 'x86 forced assertion control')
 control('--missing-ops-control', '36 ops rows required')
 mut checker := os.new_process(area + '/qf-x86-inputs')
 checker.set_args(['verify'])
 checker.set_redirect_stdio_merged()
 checker.run()
 check_output := checker.stdout_slurp()
 checker.wait()
 check_status := checker.code
 checker.close()
 os.write_file(area + '/qf-x86-inputs-verify.log', check_output)!
 os.write_file(area + '/qf-x86-inputs-verify.status', '${check_status}\n')!
 assert check_status == 0, check_output
 mut report := ['Queue-buffer followup x86 independent audit', 'Revision: bd9aa1bc1d04eac1ce31e02ce8914969294566ff']
 mut publication := map[string]string{}
 for group in ['qxo', 'qxd'] {
  work := area + '/' + group
  assert os.read_file(work + '/status')!.trim_space() == '0'
  assert os.read_file(area + '/qf-x86-' + group + '.status')!.trim_space() == '0'
  host := os.read_file(area + '/qf-x86-' + group + '.log')!
  assert !host.contains('pointer driver:')
  log := os.read_file(work + '/serial.log')!
  finished(log)
  assert lines(log, 'PERF-ROOT device=').len == 1 && log.contains(' target=/root type=ext2')
  assert log.split_into_lines().any(it.contains(' /root ext2 ')), 'actual ext2 mount table row required'
  expected := if group == 'qxo' { ['idle', 'apps'] } else { ['drag'] }
  desktop(log, work, expected)!
  if group == 'qxo' {
   verify_ops(log)
   verify_churn(log)
   verify_cache(log)
   assert lines(log, 'PERF-DRIVE ').len == 0
   report << 'ops/churn/cache: PASS 36x200 flat ops; 4x300 flat churn; no slab deltas; declared <=64MiB cache bound; private ext2 mount verified.'
  } else {
   assert lines(log, 'PERF-DRIVE drag 5').len == 1 && lines(log, 'PERF-DRIVE ').len == 1
  }
  receipt := json2.decode[map[string]string](os.read_file(work + '/receipt.json')!)!
  assert receipt['revision'] == 'bd9aa1bc1d04eac1ce31e02ce8914969294566ff'
  assert os.read_file(area + '/queue-fix/commit.txt')!.trim_space() == receipt['revision']
  assert os.read_file(area + '/queue-fix/build-x86-prod.log.status')!.trim_space() == '0'
  assert os.read_file(area + '/queue-fix/generated-review-x86-prod.status')!.trim_space() == '0'
  assert receipt['kernel_sha256'] == '27295b43e131ef9f2df0fc55f07ab5cc9ea2b3c4ff6a10227f97fb44170d337d'
  assert receipt['base_sha256'] == '883ead53512470f8472bd3391f135c669f835480ccae3c96b9bab46a6853b069'
  assert receipt['desktop_sha256'] == '637ac2337accac611a4668dd322efc15cd683a2848ec349ad13420c5adf1ea75'
  assert receipt['desktop_source_sha256'] == '027a1a810b1fd1b2b952d6a43fdbe094824ef091ce5d8dd89c001c4260ad256b'
  assert receipt['measure_source_sha256'] == '2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771'
  assert receipt['measure_sha256'] == '23e0393c69065f317874c13fb77fe5ea3a9bfc3729b5e24cca4c5d357bf2f671'
  assert receipt['curl_inputs_sha256'] == digest(area + '/qf-x86-curl/inputs.sha256')!
  assert receipt['curl_provenance_sha256'] == digest(area + '/qf-x86-curl/provenance.json')!
  for line in os.read_lines(area + '/qf-x86-curl/inputs.sha256')! {
   pin := line.split('  ')
   assert pin.len == 2 && digest(work + '/overlay/' + pin[1])! == pin[0], 'curl dependency overlay changed'
  }
  assert receipt['curl_sha256'] == digest(work + '/overlay/usr/bin/curl')!
  assert receipt['command'].contains('-device qemu-xhci,id=xhci -device usb-tablet,bus=xhci.0')
  for key, path in {
   'kernel_sha256': work + '/kernel/bin/vinix'
   'kernel_build_inputs_sha256': area + '/queue-fix/inputs-x86-prod.sha256'
   'kernel_build_log_sha256': area + '/queue-fix/build-x86-prod.log'
   'kernel_revision_sha256': area + '/queue-fix/commit.txt'
   'desktop_sha256': work + '/overlay/opt/vinix-perf/vinix-desktop-new'
   'init_source_sha256': area + '/qf-x86-tools/perf-init.sh'
   'init_sha256': work + '/overlay/sbin/init'
   'measure_source_sha256': area + '/qf-x86-tools/measure.c'
   'measure_sha256': work + '/overlay/opt/vinix-perf/measure'
   'archive_sha256': work + '/initramfs.tar'
   'iso_sha256': work + '/vm/test.iso'
  } { assert digest(path)! == receipt[key], 'input pin changed: ' + key }
  for name in ['serial.log', 'results.json', 'status', 'receipt.json'] { publication['queue-x86-' + group + '-' + name] = work + '/' + name }
  publication['queue-x86-' + group + '-harness.log'] = area + '/qf-x86-' + group + '.log'
  publication['queue-x86-' + group + '-harness-status.txt'] = area + '/qf-x86-' + group + '.status'
  for scenario in expected {
   report << lines(log, 'PERF-RESULT variant=new scenario=' + scenario + ' ')[0]
   screenshot := work + '/shots/new-' + scenario + '-1.ppm'
   publication['queue-x86-' + scenario + '.ppm'] = screenshot
   publication['queue-x86-' + scenario + '.png'] = png(screenshot)!
  }
 }
 before := area + '/qxd/shots/before-drag.ppm'
 after := area + '/qxd/shots/new-drag-1.ppm'
 start, end := window_position(before)!, window_position(after)!
 assert start != end, 'System window did not move'
 report << 'Actual drag window top border before=(${start.x},${start.y}) after=(${end.x},${end.y}); independent visual review required.'
 publication['queue-x86-drag-before.ppm'] = before
 publication['queue-x86-drag-before.png'] = png(before)!
 publication['queue-x86-wrapper.v'] = area + '/qf-x86-tools-wrapper.v'
 publication['queue-x86-prepare.v'] = area + '/qf-x86-prepare.v'
 publication['queue-x86-audit.v'] = area + '/qf-x86-audit.v'
 publication['queue-x86-audit.txt'] = area + '/qf-x86-audit.txt'
 publication['queue-x86-inputs.sha256'] = area + '/qf-x86-inputs.sha256'
 publication['queue-x86-inputs-verify.log'] = area + '/qf-x86-inputs-verify.log'
 publication['queue-x86-inputs-verify.status'] = area + '/qf-x86-inputs-verify.status'
 publication['queue-x86-inputs.v'] = area + '/qf-x86-inputs.v'
 publication['queue-x86-producer.v'] = area + '/qf-x86-producer.v'
 publication['queue-x86-tooling.tar.gz'] = area + '/qf-x86-tooling.tar.gz'
 for suffix, source in {
  'queue-x86-curl-inputs.sha256': area + '/qf-x86-curl/inputs.sha256'
  'queue-x86-curl-provenance.json': area + '/qf-x86-curl/provenance.json'
  'queue-x86-curl-notes.txt': area + '/qf-x86-curl/notes.txt'
  'queue-x86-curl-setup.v': area + '/qf-x86-curl-setup.v'
  'queue-x86-initial-preserve.v': area + '/qf-x86-preserve-initial.v'
  'queue-x86-initial-records.json': area + '/qf-x86-initial-missing-curl/records.json'
  'queue-x86-initial-failure.txt': area + '/qf-x86-initial-missing-curl/failure.txt'
  'queue-x86-initial-inputs.sha256': area + '/qf-x86-initial-missing-curl/qf-x86-inputs.sha256'
  'queue-x86-initial-tooling.tar.gz': area + '/qf-x86-initial-missing-curl/qf-x86-tooling.tar.gz'
  'queue-x86-initial-serial.log': area + '/qf-x86-initial-missing-curl/qxo/serial.log'
  'queue-x86-initial-status': area + '/qf-x86-initial-missing-curl/qxo/status'
  'queue-x86-initial-receipt.json': area + '/qf-x86-initial-missing-curl/qxo/receipt.json'
  'queue-x86-initial-harness.log': area + '/qf-x86-initial-missing-curl/qf-x86-qxo.log'
  'queue-x86-initial-harness-status.txt': area + '/qf-x86-initial-missing-curl/qf-x86-qxo.status'
 } { publication[suffix] = source }
 report << 'Initial userspace attempt failed exit1 at missing genuine curl (errno2/status127), before DONE. Its raw logs/status/receipt/frozen122-input manifest and tooling are preserved separately. Final full replay uses the same Q2 kernel and unchanged workload with a pinned genuine x86 curl/dependency overlay.'
 for suffix, source in {
  'queue-x86-kernel-inputs.sha256': area + '/queue-fix/inputs-x86-prod.sha256'
  'queue-x86-kernel-build.log': area + '/queue-fix/build-x86-prod.log'
  'queue-x86-kernel-build.status': area + '/queue-fix/build-x86-prod.log.status'
  'queue-x86-kernel-revision.txt': area + '/queue-fix/commit.txt'
  'queue-x86-kernel-generated-review.log': area + '/queue-fix/generated-review-x86-prod.log'
  'queue-x86-kernel-generated-review.status': area + '/queue-fix/generated-review-x86-prod.status'
 } { publication[suffix] = source }
 mut pins := []string{}
 for suffix, path in publication {
  if suffix.ends_with('-audit.txt') { continue }
  assert os.is_file(path), path
  pins << digest(path)! + '  ' + path
 }
 pins.sort()
 os.write_file(area + '/qf-x86-publication.sha256', pins.join('\n') + '\n')!
 report << 'Two strict negative controls rejected; all receipt/input pins and raw/JSON desktop rows verified.'
 os.write_file(area + '/qf-x86-audit.txt', report.join('\n') + '\n')!
 os.write_file(area + '/queue-desktop-publication-inputs.json', json2.encode(publication, prettify: true) + '\n')!
 println(report.join('\n'))
}
