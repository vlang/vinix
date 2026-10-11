import crypto.sha256
import json2
import os

struct Evidence {
 architecture string
 context string
 inputs map[string]string
 source_inputs map[string]string
 verdicts []string
}
fn hash(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn main() {
 root := '/Users/alex/code/vinix/'
 area := '/Volumes/VinixLinuxCompatPressure1012/'
 output := root + 'tests/linux-compat/results/2026-10-12/'
 inventory := json2.decode[json2.Any](os.read_file(root + 'docs/linux-syscall-coverage.json')!)!.as_map()['inputs']!.as_map()
 assert inventory.len == 49
 mut negative := os.new_process('/Volumes/VinixLinuxCompatNext1011/tmp/assert-check')
 negative.set_redirect_stdio()
 negative.run()
 negative_output := negative.stdout_slurp() + negative.stderr_slurp()
 negative.wait()
 assert negative.code == 1 && negative_output.contains('receipt audit failure must be fatal')
 negative.close()
 for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
  tree := '/Volumes/VinixLinuxCompatContinue1011/' + suffix + '/'
  mut sources := map[string]string{}
  for path, value in inventory {
   assert hash(root + path) == value.str()
   assert hash(tree + path) == value.str()
   sources[path] = value.str()
  }
  blob := os.read_file(tree + 'kernel/obj/blob.c')!
  dump_body := blob.all_after('void proc__dump_threads(void) {').all_before('// The first fields of')
  assert dump_body.len > 1000
  try_lock := dump_body.index('Lock__test_and_acquire') or { panic('missing nonblocking lock') }
  state_read := dump_body.index('proc__process_state_unlocked') or { panic('missing locked state') }
  assert try_lock < state_read
  assert !dump_body[..state_read].contains('proc__process_state(process)')
  // Bound the function by its table-unlock epilogue, rather than later users.
  function := dump_body.all_before('proc__unlock_table();')
  assert function.count('printf_benchmark(') == if arch == 'x86_64' { 2 } else { 0 }
  final_kernel := hash(tree + 'kernel/bin/vinix')
  mut fixture_hash := ''
  for phase in ['before', 'after'] {
   state := area + 'sysrq-' + phase + '-' + suffix
   raw := os.read_file(state + '/receipt.json')!
   receipt := json2.decode[json2.Any](raw)!.as_map()
   assert receipt['architecture']!.str() == arch
   assert receipt['kernel_sha256']!.str() == hash(state + '/kernel/bin/vinix')
   if phase == 'after' { assert receipt['kernel_sha256']!.str() == final_kernel }
   rows := receipt['results']!.as_array()
   assert rows.len == if phase == 'before' { 1 } else { 3 }
   mut names := map[string]bool{}
   for row in rows {
    item := row.as_map()
    name := item['name']!.str()
    assert name !in names
    names[name] = true
    assert item['source_sha256']!.str() == hash(root + 'tests/linux-compat/' + name + 'fixture/core.v')
    assert item['source_sha256']!.str() == hash(state + '/sources/' + name + 'fixture/core.v')
    assert item['init_sha256']!.str() == hash(state + '/' + name + '/init')
    assert item['iso_sha256']!.str() == hash(state + '/' + name + '/test.iso')
    assert item['exit_code']!.int() == if phase == 'before' && arch == 'x86_64' { 1 } else { 0 }
    if name == 'sysrq' {
     if phase == 'before' { fixture_hash = item['source_sha256']!.str() }
     else { assert fixture_hash == item['source_sha256']!.str() }
    }
   }
   assert names['sysrq']
   log := os.read_file(state + '.log')!
   assert log.contains('LINUX SYSRQ: PASS')
   assert !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
   actual_rows := log.split_into_lines().filter(it.starts_with('sysrq: pid=1 ppid=0 tid=1')).len
   assert actual_rows == if phase == 'before' && arch == 'x86_64' { 0 } else { 2 }
   if phase == 'before' && arch == 'x86_64' {
    assert log.contains("Missing verdicts: ['sysrq: pid=1 ppid=0 tid=1']")
   } else { assert log.contains('Linux compatibility guest suite: PASS') }
   name := 'sysrq-' + phase + '-' + arch
   assert !os.exists(output + name + '.json') && !os.exists(output + name + '.log')
   os.write_file(output + name + '.json', raw)!
   os.write_file(output + name + '.log', log)!
  }
  inspection := area + 'sysrq-inspection-' + suffix
  log := os.read_file(inspection + '/serial.log')!
  verdicts := ['PASS: dumpability state and credential lifecycle',
   'PASS: process VM copies, faults, COW, vectors and failures',
   'PASS: inspection authorization and dumpability revocation',
   'PASS: process VM inspection races with exec and exit',
   'PASS: process VM inspection races with munmap and remap',
   'PASS: remote inspection preserves cgroup memory limits',
   'VINIX PROCESS INSPECTION: PASS']
  for verdict in verdicts { assert log.contains(verdict) }
  assert !log.contains('FAIL:') && !log.contains('KERNEL PANIC') && !log.contains('FATAL EXCEPTION')
  assert hash(tree + 'kernel/bin/vinix') == final_kernel
  mut inputs := {'kernel': final_kernel, 'init': hash(inspection + '/init'),
   'archive': hash(inspection + '/initramfs.tar'), 'iso': hash(inspection + '/test.iso'),
   'generated_c': hash(tree + 'kernel/obj/blob.c'), 'build_log': hash(area + 'sysrq-build4-' + suffix + '.log'),
   'inventory': hash(root + 'docs/linux-syscall-coverage.json'), 'audit_source': hash(@FILE),
   'compiler': hash('/Users/alex/code/v/v'), 'assertion_control': hash('/Volumes/VinixLinuxCompatNext1011/tmp/assert-check')}
  for path in ['tests/process-inspection/test.c', 'tests/native-guest-tools/generic-main.v',
   'tests/native-guest-tools/guesthost/build.v', 'tests/native-guest-tools/guesthost/cli.v',
   'tests/linux-compat/run.v', 'tests/linux-compat/sysrqfixture/core.v'] { inputs[path] = hash(root + path) }
  name := 'sysrq-inspection-' + arch
  assert !os.exists(output + name + '.json') && !os.exists(output + name + '.log')
  os.write_file(output + name + '.json', json2.encode(Evidence{arch,
   'production native kernel; nonblocking task-list state; ordinary-user SysRq denied; repeated serial dumps; process inspection regression; assertion-enabled audit (-nocache -cflags -O2)',
   inputs, sources, verdicts}, prettify: true) + '\n')!
  os.write_file(output + name + '.log', log)!
  println(arch + ': before/after serial controls, 49 source hashes and inspection verdicts verified')
 }
 assert !os.exists(output + 'sysrq-audit.v')
 os.cp(@FILE, output + 'sysrq-audit.v')!
}
