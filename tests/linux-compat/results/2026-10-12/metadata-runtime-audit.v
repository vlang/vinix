import crypto.sha256
import json2
import os

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }

fn guest_file(state string, absolute string) string {
 root := state + '/rootfs'
 mut path := root + absolute
 mut hops := 0
 for os.is_link(path) {
  hops++
  assert hops <= 40
  link := os.readlink(path) or { panic(err) }
  path = os.norm_path(if link.starts_with('/') { root + link } else { os.dir(path) + '/' + link })
  assert path.starts_with(root + '/')
 }
 return path
}

fn main() {
 area := '/Volumes/VinixLinuxCompatPressure1012'
 root := '/Users/alex/code/vinix'
 out := root + '/tests/linux-compat/results/2026-10-12/'
 staged := '/Volumes/VinixLinuxCompatContinue1011/native-runtime-inputs3-x86'
 packages := json2.decode[json2.Any](os.read_file(staged + '/inputs.json')!)!.as_map_of_strings()
 assert packages['stager_source'] == digest('/tmp/vinix-linux-runtime-stage.v')
 for url, hash in packages {
  if url == 'stager_source' { continue }
  file := if url.ends_with('APKINDEX.tar.gz') {
   staged + '/' + if url.contains('/main/') { 'main' } else { 'community' } + '/APKINDEX.tar.gz'
  } else { staged + '/archives/' + url.all_after_last('/') }
  assert digest(file) == hash
 }
 mut manifest_hash := ''
 for language in ['go', 'java'] {
  state := area + '/metadata-' + language + '-' + if language == 'go' { 'user' } else { 'root' } + '-x86'
  raw := os.read_file(state + '/guest-report.json')!
  report := json2.decode[json2.Any](raw)!.as_map()
  receipt := json2.decode[json2.Any](os.read_file(state + '/application-inputs.json')!)!.as_map()
  inputs := receipt['inputs']!.as_map_of_strings()
  uid := if language == 'go' { 1000 } else { 0 }
  assert receipt['exit_code']!.int() == 0 && receipt['uid']!.int() == uid
  assert receipt['memory_mib']!.int() == 2048 && receipt['workload_timeout']!.int() == 600
  assert receipt['architecture']!.str() == 'x86_64' && receipt['execution_path']!.str() == 'native-x86_64'
  assert report['context']!.str() == 'vinix-guest' && report['execution_path']!.str() == 'native-x86_64'
  assert report['uid']!.int() == uid && report['gid']!.int() == uid
  assert inputs['guest_report'] == sha256.sum(raw.trim_space().bytes()).hex()
  assert inputs['workloads'] == report['suite_sha256']!.str() && inputs['workloads'] == digest(state + '/rootfs/usr/bin/linux-compat-workloads')
  assert inputs['runtime-probe'] == report['runtime_probe_sha256']!.str() && inputs['runtime-probe'] == digest(state + '/rootfs/usr/share/linux-compat/runtime')
  assert inputs['kernel'] == json2.decode[json2.Any](os.read_file(area + '/metadata-after2-x86/receipt.json')!)!.as_map()['kernel_sha256']!.str()
  assert inputs['kernel'] == inputs['snapshot_kernel'] && inputs['kernel'] == digest(state + '/kernel/bin/vinix')
  assert inputs['guest_options'] == digest(state + '/rootfs/etc/linux-compat-options')
  assert inputs['guest_credentials'] == digest(state + '/rootfs/etc/linux-compat-uid')
  assert inputs['init_source'] == digest(root + '/tests/linux-compat/appinitfixture/core.v')
  assert inputs['rootfs_manifest'] == digest(state + '/rootfs-inputs.json')
  if language == 'go' { manifest_hash = inputs['rootfs_manifest'] }
  else { assert inputs['rootfs_manifest'] == manifest_hash }
  manifest := json2.decode[json2.Any](os.read_file(state + '/rootfs-inputs.json')!)!.as_map_of_strings()
  for path, value in manifest {
   source := state + '/rootfs' + path
   if path == '/sbin/init' {
    assert digest(source) == digest(state + '/init')
    continue
   }
   if value.starts_with('link:') { assert os.is_link(source) && os.readlink(source)! == value.all_after('link:'); continue }
   fields := value.split(':')
   assert (os.stat(source)!.mode & 0o7777).str() == fields[1]
   if fields[0] == 'file' { assert digest(source) == fields[2], 'prepared root changed: ' + path }
   else { assert fields[0] == 'directory' && os.is_dir(source) }
  }
  results := report['results']!.as_array()
  assert results.len == 1 && results[0].as_map()['name']!.str() == language
  assert results[0].as_map()['status']!.str() == 'passed'
  commands := report['commands']!.as_array()
  assert commands.len == if language == 'go' { 3 } else { 5 }
  for command in commands {
   row := command.as_map()
   assert row['exit_code']!.int() == 0 && !row['timed_out']!.bool() && !row['output_limited']!.bool()
   executable := row['argv']!.as_array()[0].str()
   assert executable.starts_with('/')
   if executable == '/tmp/linux-compat-evidence/go-smoke' {
    assert language == 'go'
    compiler := commands[1].as_map()['argv']!.as_array().map(it.str())
    assert compiler == ['/usr/bin/go', 'build', '-o', executable, '/tmp/linux-compat-evidence/smoke.go']
    hash := row['executable_sha256']!.str()
    assert hash.len == 64 && hash.bytes().all(it in '0123456789abcdef'.bytes())
   } else { assert row['executable_sha256']!.str() == digest(guest_file(state, executable)) }
  }
  assert commands.last().as_map()['stdout']!.str().contains(if language == 'go' { 'GO SMOKE PASS' } else { 'on Vinix: PASS' })
  for source, name in {'guest-report.json': 'metadata-' + language + '-x86_64.json', 'application-inputs.json': 'inputs-' + 'metadata-' + language + '-x86_64.json', 'serial.log': 'metadata-' + language + '-x86_64.log'} {
   assert !os.exists(out + name)
   os.cp(state + '/' + source, out + name)!
  }
  println(language + ': actual guest commands, identities and all input hashes verified')
 }
 for source, name in {staged + '/inputs.json': 'metadata-runtime-packages-x86_64.json', area + '/sparse-go-user-x86/rootfs-inputs.json': 'metadata-runtime-rootfs-x86_64.json', '/tmp/vinix-linux-runtime-stage.v': 'metadata-runtime-acquisition-x86_64.v'} {
  assert !os.exists(out + name)
  os.cp(source, out + name)!
 }
}
