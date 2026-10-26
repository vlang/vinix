// SPDX-License-Identifier: GPL-2.0-or-later
// Included verbatim by intent-uri371-run-generate.v after its module line.
module main

fn canonical_key(key string) bool {
 return key != '' && !key.starts_with('/') && !key.ends_with('/')
  && key.split('/').all(it != '' && it != '.' && it != '..')
}

fn control_file(key string) bool {
 return key.starts_with('run-old/') || key.starts_with('native-old/')
  || key.starts_with('apk/') || key.starts_with('commands/')
  || key in ['old.json', 'config.json', 'build-pins.json', 'old-inputs-before.json',
   'old-inputs-after.json', 'shared-inputs.json', 'old-semantic-check.json',
   'source/intent-uri369-run.v', 'tools/checked-runner', 'tools/suite']
}

fn retain_control() ! {
 assert !os.exists(state + '/control369')
 assert hash(snapshot + '/files.json')! == original_inventory
 assert hash(snapshot + '/receipt.json')! == original_receipt
 original := read_map(snapshot + '/files.json')!
 proof := object(snapshot + '/receipt.json')!
 assert proof['status']!.str() == 'preserved-real-new-art-failure'
 assert proof['original_root']!.str() == origin
 assert proof['original_files_sha256']!.str() == original_inventory
 assert proof['original_file_count']!.int() == original.len
 assert original['apk/probe.apk']! == original_apk
 mut paths := map[string]string{}
 mut pins := map[string]string{}
 for key, pin in original {
  assert canonical_key(key) && canonical_pin(pin)
  if !control_file(key) { continue }
  dest := 'files/' + key
  assert hash(origin + '/' + key)! == pin
  clone(origin + '/' + key, state + '/control369/' + dest)!
  paths[dest] = origin + '/' + key
  pins[dest] = pin
 }
 adjacent := read_map(snapshot + '/adjacent.json')!
 assert hash(snapshot + '/adjacent.json')! == proof['adjacent_inventory_sha256']!.str()
 for label in ['prepare', 'old', 'new'] {
  for suffix in ['-before.json', '-command.json', '.log'] {
   path := '/Users/alex/.local/state/vinix/android/intent-uri369-fixture-' + label + '-2026-10-26' + suffix
   dest := 'actions/' + label + suffix
   assert hash(path)! == adjacent[path]!
   clone(path, state + '/control369/' + dest)!
   paths[dest] = path
   pins[dest] = adjacent[path]!
  }
 }
 write_json(state + '/control-origin.json', paths)!
 write_json(state + '/control-sha256.json', pins)!
 clone(snapshot + '/files.json', state + '/control-origin-inventory.json')!
 clone(snapshot + '/receipt.json', state + '/control-failure-receipt.json')!
}

// Check the original complete file set without rehashing the whole historic
// framework. Selected control bytes are rehashed both at origin and in371.
fn names(root string, prefix string, mut found map[string]bool) ! {
 for name in os.ls(root + '/' + prefix)! {
  key := if prefix == '' { name } else { prefix + '/' + name }
  assert canonical_key(key)
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { names(root, key, mut found)! }
   .regular { found[key] = true }
   else { return error('nonregular original evidence: ' + key) }
  }
 }
}

fn check_control(receipt string) ! {
 assert !os.exists(receipt) && !os.exists(state + '/sha256.json')
 assert os.real_path(origin) == origin && !os.is_link(origin)
 pins := read_map(state + '/control-sha256.json')!
 paths := read_map(state + '/control-origin.json')!
 complete := read_map(state + '/control-origin-inventory.json')!
 proof := object(state + '/control-failure-receipt.json')!
 assert hash(state + '/control-origin-inventory.json')! == original_inventory
 assert hash(state + '/control-failure-receipt.json')! == original_receipt
 assert hash(snapshot + '/files.json')! == original_inventory
 assert hash(snapshot + '/receipt.json')! == original_receipt
 assert proof['status']!.str() == 'preserved-real-new-art-failure' && proof['original_root']!.str() == origin
 assert hash(snapshot + '/adjacent.json')! == proof['adjacent_inventory_sha256']!.str()
 adjacent := read_map(snapshot + '/adjacent.json')!
 mut present := map[string]bool{}
 names(origin, '', mut present)!
 assert present.keys().sorted() == complete.keys().sorted(), 'complete original369 root remains required'
 mut expected_keys := []string{}
 for key, _ in complete { if control_file(key) { expected_keys << 'files/' + key } }
 for label in ['prepare', 'old', 'new'] {
  for suffix in ['-before.json', '-command.json', '.log'] { expected_keys << 'actions/' + label + suffix }
 }
 assert pins.keys().sorted() == expected_keys.sorted() && paths.keys().sorted() == pins.keys().sorted()
 mut retained_files := map[string]string{}
 inventory(state + '/control369', '', mut retained_files)!
 assert retained_files == pins, 'exact retained control file set and bytes'
 for key, pin in pins {
  assert canonical_key(key) && canonical_pin(pin)
  expected_path := if key.starts_with('files/') { origin + '/' + key.all_after('files/') }
   else {
    part := key.all_after('actions/')
    label := if part.starts_with('prepare') { 'prepare' } else if part.starts_with('old') { 'old' } else { 'new' }
    '/Users/alex/.local/state/vinix/android/intent-uri369-fixture-' + label + '-2026-10-26' + part.all_after(label)
   }
  assert paths[key]! == expected_path && hash(expected_path)! == pin
  if key.starts_with('files/') { assert complete[key.all_after('files/')]! == pin }
  else { assert adjacent[expected_path]! == pin }
 }
 c := state + '/control369/files'
 for phase in ['before', 'after'] {
  assert read_map(c + '/old-inputs-' + phase + '.json')! == read_map(c + '/shared-inputs.json')!
 }
 for key, pin in read_map(c + '/shared-inputs.json')! { assert complete[key]! == pin }
 suite := object(c + '/commands/suite-old.json')!
 assert suite['argv']!.as_array().map(it.str()) == [origin + '/tools/suite', origin + '/old.json']
 assert suite['exit_code']!.int() == 0 && suite['executable_sha256']!.str() == hash(c + '/tools/suite')!
 assert hash(c + '/tools/suite')! == hash(state + '/tools/suite')!
 action := object(state + '/control369/actions/old-command.json')!
 assert action['argv']!.as_array().map(it.str()) == [origin + '/tools/checked-runner', 'old']
 assert action['exit_code']!.int() == 0 && action['executable_sha256_before']!.str() == original_runner
 assert action['executable_sha256_after']!.str() == original_runner
 assert hash(c + '/tools/checked-runner')! == original_runner
 assert action['output_sha256']!.str() == hash(state + '/control369/actions/old.log')!
 before := object(state + '/control369/actions/old-before.json')!
 assert before['argv']! == action['argv']!
 assert before['executable_sha256_before']!.str() == original_runner
 config := object(c + '/old.json')!
 assert config['native_dir']!.str() == origin + '/native-old'
 assert config['output']!.str() == '/Users/alex/code/vinix/build/android-maps/intent-uri369-old'
 apps := config['applications']!.as_array()
 assert apps.len == 1 && apps[0].as_map()['apk']!.str() == origin + '/apk/probe.apk'
 assert apps[0].as_map()['startup_seconds']!.int() == 35
 apk := hash(c + '/apk/probe.apk')!
 assert apk == original_apk && hash(state + '/apk/probe.apk')! == apk
 raw := json2.decode[[]map[string]json2.Any](os.read_file(c + '/run-old/results.json')!)!
 assert raw.len == 1
 serial := c + '/run-old/bootstrap-fixture/serial.log'
 semantic_at('old', raw[0], os.read_file(serial)!, apk, origin + '/apk/probe.apk')!
 prior := read_map(c + '/old-semantic-check.json')!
 assert prior['variant']! == 'old' && prior['status']! == 'expected-result-pass'
 assert prior['checker_binary_sha256']! == original_runner
 assert prior['serial_sha256']! == hash(serial)!
 assert prior['raw_results_sha256']! == hash(c + '/run-old/results.json')!
 assert prior['signed_apk_sha256']! == apk && prior['native_sha256']! == native_pin
 assert prior['old_framework_sha256']! == old367_jar && prior['new_framework_sha256']! == original_new_jar
 assert prior['raw_outcome']! == 'startup_failed'
 mut old := map[string]string{}
 mut native := map[string]string{}
 inventory(c + '/native-old', '', mut old)!
 inventory(state + '/native-old', '', mut native)!
 assert old == native && old['api-impl.jar']! == old367_jar
 write_json(receipt, {'variant': 'old', 'status': 'retained-old-control-pass',
  'original_root': origin, 'original_inventory_sha256': original_inventory,
  'retained_map_sha256': hash(state + '/control-sha256.json')!,
  'original_semantic_receipt_sha256': hash(c + '/old-semantic-check.json')!,
  'original_old_action_sha256': hash(state + '/control369/actions/old-command.json')!,
  'serial_sha256': hash(serial)!, 'raw_results_sha256': hash(c + '/run-old/results.json')!,
  'signed_apk_sha256': apk, 'native_sha256': native_pin, 'old_framework_sha256': old367_jar,
  'new_framework_sha256': read_map(state + '/build-pins.json')!['framework_jar']!,
  'checker_source_sha256': hash(state + '/source/intent-uri371-run.v')!,
  'scope': 'Retained and rehashed actual369 old367 ART control. Original historical paths and original complete root remain required. No new old guest was launched. Unchanged direct parseUri oracle and byte-identical signed APK; full native closure equals fresh371 native-old, qualified separately against353.'})!
 println('INTENT-URI-RETAINED-OLD-CONTROL-PASS')
}
