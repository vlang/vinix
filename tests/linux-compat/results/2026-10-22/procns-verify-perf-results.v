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

fn verify_desktop(log string) ! {
 mut results := map[string]map[string]string{}
 for line in lines(log, 'PERF-RESULT ') {
  row := fields(line.all_after('PERF-RESULT '))
  scenario := row['scenario']
  assert scenario in ['idle', 'apps', 'drag'] && scenario !in results
  label(row, scenario)
  assert row.len == 13 && row['seconds'] == '5.0'
  processes := natural(row['processes'])
  assert processes > 0
  for key in ['desktop_cpu', 'apps_cpu', 'total_cpu', 'desktop_mb', 'apps_mb', 'total_mb', 'system_used_mb', 'physical_mb'] {
   assert decimal(row[key]) <= 16384
  }
  assert decimal(row['total_mb']) > 0 && decimal(row['physical_mb']) > 0
  prefix := 'variant=new scenario=' + scenario + ' round=1'
  ready := lines(log, 'PERF-READY ' + prefix + ' after ')
  assert ready.len == 1
  ready_seconds := ready[0].all_after(' after ').all_before('s')
  assert natural(ready_seconds) <= 120
  assert lines(log, 'PERF-SHOT ' + prefix).len == 1
  procs := lines(log, 'PERF-PROC ' + prefix + ' ')
  assert procs.len == int(processes)
  mut pids := map[u64]bool{}
  for process in procs {
   data := fields(process.all_after('PERF-PROC '))
   pid := natural(data['pid'])
   assert pid > 0 && pid !in pids
   pids[pid] = true
  }
  if scenario in ['apps', 'drag'] {
   for name in ['vinix-activity', 'vinix-terminal', 'vinix-calculator', 'vinix-clock'] {
    assert procs.any(it.contains('/usr/bin/' + name + '[')), 'missing app process: ' + scenario + ' ' + name
   }
  }
  results[scenario] = row
 }
 assert results.len == 3
 assert lines(log, 'PERF-READY ').len == 3 && lines(log, 'PERF-SHOT ').len == 3
 assert lines(log, 'PERF-DRIVE ').len == 1 && lines(log, 'PERF-DRIVE drag 5').len == 1
 array := (json2.decode[json2.Any](os.read_file(area + '/perf-compat-desktop.json')!)!).as_array()
 assert array.len == 3
 mut seen := map[string]bool{}
 for item in array {
  row := item.as_map()
  scenario := row['scenario']!.str()
  assert scenario in results && scenario !in seen
  seen[scenario] = true
  for key, value in results[scenario] { assert row[key]!.str() == value, scenario + ' JSON/raw mismatch: ' + key }
 }
}

fn control(args []string, marker string) {
 mut p := os.new_process(os.executable())
 p.set_args(args)
 p.set_redirect_stdio_merged()
 p.run()
 output := p.stdout_slurp()
 p.wait()
 code := p.code
 p.close()
 assert code == 1 && output.contains(marker), 'negative control failed to reject: ' + output
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--assertion-control' { assert false, 'perf forced assertion control'; return }
 if os.args.len == 2 && os.args[1] == '--missing-ops-control' { verify_ops(os.read_file(area + '/perf-compat-desktop/serial.log')!); return }
 assert os.args.len == 1
 control(['--assertion-control'], 'perf forced assertion control')
 control(['--missing-ops-control'], '36 ops rows required')
 for group in ['perf-small-ops', 'perf-compat-desktop'] {
  assert os.read_file(area + '/' + group + '.status')!.trim_space() == '0'
  log := os.read_file(area + '/' + group + '/serial.log')!
  finished(log)
  if group == 'perf-small-ops' {
   verify_ops(log)
   verify_churn(log)
   verify_cache(log)
   assert lines(log, 'PERF-RESULT ').len == 0
   println('ARM ops/churn/cache: PASS (36x200 flat operations; 4x300 flat churn; declared cache bound)')
  } else {
   verify_desktop(log)!
   println('ARM desktop: PASS (idle/apps/drag, five seconds each, raw/JSON and required app processes)')
  }
 }
 println('Perf raw-result audit: PASS (two negative controls rejected)')
}
