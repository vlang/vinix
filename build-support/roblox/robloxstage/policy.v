// SPDX-License-Identifier: GPL-2.0-or-later
module robloxstage

import androidhost as ah

fn binary(name string, left string, right ah.Value) !string { return call('operator.' + name, o(left), right)! }
fn divided(left string, right ah.Value) !string {
 result := binary('truediv', left, right) or { release([left])!; return err }
 release([left])!
 return result
}
fn path(base string, component string) !string { return binary('truediv', base, v(ah.Value(component))!)! }
fn global_path(base string, component string) !string { return divided(global(base)!, v(ah.Value(component))!)! }
fn temporary_member(id string, name string) !string {
 result := member(id,name) or { release([id])!; return err }
 release([id])!
 return result
}
fn field(mapping string, name string) !string { return get(mapping, name)! }
fn named(mut f Frame, name string, value string) !string {
 id := f.named(name, value)!
 assign(f.pins, name, id)!
 return id
}
fn assign(mapping string, name string, value string) ! {
 release([call('operator.setitem', o(mapping), v(ah.Value(name))!, o(value))!])!
}
fn fail(message string) !string {
 error_ := call('RuntimeError', o(literal(ah.Value(message))!))!
 return invoke_owned(global('_raise_actual')!, [o(error_)], {}, [error_])!
}
fn fail_path(prefix string, value string) !string {
 factory := global('RuntimeError')!
 message_ := message(prefix, value, '') or { release([factory])!; return err }
 error_ := invoke_owned(factory, [o(message_)], {}, [message_])!
 return invoke_owned(global('_raise_actual')!, [o(error_)], {}, [error_])!
}
fn exists_file(value string) !bool { return tested(method(value, 'is_file', [], {})!)! }
fn access(value string) !bool {
 target := global('os.access')!
 flag := global('os.X_OK') or { release([target])!; return err }
 return tested(invoke_owned(target, [o(value), o(flag)], {}, [flag])!)!
}
fn mapping_equal(value string, name string, expected ah.Value) !bool {
 return !compared('ne', method(value, 'get', [v(ah.Value(name))!], {})!, expected)!
}
fn provenance(state string, mut f Frame) !string {
 android := named(mut f, 'android_stage', call('Path', o(f.names['android_stage']))!)!
 prefix_operand := global('PREFIX')!
 runtime_value := binary('truediv', android, o(prefix_operand)) or { release([prefix_operand])!; return err }
 release([prefix_operand])!
 runtime := named(mut f, 'runtime', runtime_value)!
 launcher := named(mut f, 'android_launcher', path(android, 'usr/bin/run-android')!)!
 if !exists_file(launcher)! || !access(launcher)! {
  return fail('Build the native Android runtime with ./scripts/build-android-aarch64.sh first')!
 }
 left := call('digest', o(launcher))!
 target := global('digest')!
 source := global_path('ROOT', 'build-support/android/run-android')!
 right := invoke_owned(target, [o(source)], {}, [source])!
 comparison := call('operator.ne', o(left), o(right)) or { release([left,right])!; return err }
 release([left,right])!
 unequal := tested(comparison)!
 if unequal { return fail('Android runtime has a stale launcher; rebuild the Android layer')! }
 art := named(mut f, 'art', call('art_tools')!)!
 art_manifest := named(mut f, 'art_manifest', method(art, 'read_manifest', [o(runtime)], {})!)!
 bionic := named(mut f, 'bionic_manifest', method(art, 'read_bionic_manifest', [o(runtime)], {})!)!
 atl := named(mut f, 'atl_manifest', method(art, 'read_atl_manifest', [o(runtime)], {})!)!
 musl := named(mut f, 'musl_manifest', temporary_method(call('musl_tools')!, 'read_manifest', [o(runtime)], {})!)!
 perform_method(art, 'validate_atl_art_pair', [o(art_manifest),o(atl)], {})!
 receipt := named(mut f, 'receipt', path(runtime, 'runtime-manifest.json')!)!
 loader := global('json.loads')!
 content := method(receipt, 'read_text', [], {})!
 manifest := named(mut f, 'manifest', invoke_owned(loader, [o(content)], {}, [content])!)!
 instance_checker := global('isinstance')!
 dictionary := global('dict')!
 mut valid := tested(invoke_owned(instance_checker, [o(manifest),o(dictionary)], {}, [dictionary])!)!
 if valid { valid = mapping_equal(manifest, 'architecture', v(ah.Value('aarch64'))!)! }
 if valid { valid = mapping_equal(manifest, 'execution', v(ah.Value('native'))!)! }
 if valid { valid = mapping_equal(manifest, 'page_size', v(ah.Value(16384))!)! }
 if valid {
  target_ := member(manifest, 'get')!
  actual := invoke(target_, [v(ah.Value('runtime_prefix'))!], {})!
  prefix_source := global('PREFIX')!
  prefix := added(literal(ah.Value('/'))!, o(prefix_source)) or { release([prefix_source])!; return err }
  release([prefix_source])!
  comparison_ := call('operator.ne', o(actual), o(prefix)) or { release([actual,prefix])!; return err }
  release([actual,prefix])!
  valid = !tested(comparison_)!
 }
 if valid {
  architecture := temporary_method(path(runtime, 'architecture')!, 'read_text', [], {})!
  valid = !compared('ne', temporary_method(architecture, 'strip', [], {})!, v(ah.Value('aarch64'))!)!
 }
 if valid { valid = mapping_equal(manifest, 'art', o(art_manifest))! }
 if valid { valid = tested(method(art_manifest, 'get', [v(ah.Value('bootclasspath'))!], {})!)! }
 if valid { valid = mapping_equal(manifest, 'bionic', o(bionic))! }
 if valid { valid = mapping_equal(manifest, 'atl', o(atl))! }
 if valid { valid = mapping_equal(manifest, 'musl', o(musl))! }
 if !valid { return fail('Roblox requires the verified native ARM64 Android runtime')! }
 compatibility := named(mut f, 'compatibility', path(runtime, 'usr/lib/libvinix-android-compat.so')!)!
 if !exists_file(compatibility)! { return fail('Android runtime is missing its native compatibility library')! }
 target_ := member(art, '_elf')!
 loader_path := path(runtime, 'lib/ld-musl-aarch64.so.1')!
 release([invoke_owned(target_, [o(loader_path)], {'required': v(ah.Value(true))!}, [loader_path])!])!
 perform_method(art, '_elf', [o(compatibility)], {'required': v(ah.Value(true))!})!
 return provenance_result(mut f)!
}

fn validate(state string, mut f Frame) !string {
 stage := named(mut f, 'stage', call('Path', o(f.names['stage']))!)!
 if tested(method(stage, 'is_symlink', [], {})!)! || !tested(method(stage, 'is_dir', [], {})!)! {
  return fail_path('Roblox staging must be a directory: ', stage)!
 }
 expected := named(mut f, 'expected', call('provenance', o(f.names['android_stage']))!)!
 target := global('set')!
 files := field(expected, 'files')!
 left := invoke_owned(target, [o(files)], {}, [files])!
 right := call('_singleton', o(global('RECEIPT')!))!
 required := named(mut f, 'required', binary('or_', left, o(right)) or { release([right,left])!; return err })!
 release([right,left])!
 actual := named(mut f, 'actual', call('set')!)!
 iterator := temporary_iter(method(stage, 'rglob', [v(ah.Value('*'))!], {})!)!
 f.names['private-iterator'] = iterator
 for {
  row := callback('next', {'owner': ah.Value(iterator)})!.object()
  if ah.field(row, 'done') as bool { break }
  entry := named(mut f, 'path', ah.field(row, 'value').text())!
  if tested(method(entry, 'is_symlink', [], {})!)! {
   release([iterator])!
   return fail_path('Roblox staging contains a symlink: ', entry)!
  }
  if exists_file(entry)! {
   target_ := member(actual, 'add')!
   relative := method(entry, 'relative_to', [o(stage)], {})!
   text_ := temporary_method(relative, 'as_posix', [], {})!
   release([invoke_owned(target_, [o(text_)], {}, [text_])!])!
  }
  f.clean()!
 }
 release([iterator])!
 if compare('ne', actual, o(required))! { return fail('Roblox staging must contain only its native APK launchers and manifest')! }
 manifest := named(mut f, 'manifest', call('_read_receipt', o(stage))!)!
 if compare('ne', manifest, o(expected))! { return fail('Roblox staging does not match its native Android runtime; rebuild the Roblox layer')! }
 entries := temporary_method(field(expected, 'files')!, 'items', [], {})!
 iterator2 := temporary_iter(entries)!
 f.names['private-iterator'] = iterator2
 for {
  row := callback('next', {'owner': ah.Value(iterator2)})!.object()
  if ah.field(row, 'done') as bool { break }
  pair_ := pair(ah.field(row, 'value').text())!
  name := named(mut f, 'name', pair_[0])!
  checksum := named(mut f, 'checksum', pair_[1])!
  entry := named(mut f, 'path', binary('truediv', stage, o(name))!)!
  checker := global('stat.S_ISREG')!
  mode := temporary_member(method(entry, 'stat', [], {})!, 'st_mode')!
  mut valid := tested(invoke_owned(checker, [o(mode)], {}, [mode])!)!
  if valid { valid = access(entry)! }
  if valid { valid = !compared('ne', call('digest', o(entry))!, o(checksum))! }
  if !valid { release([iterator2])!; return fail_path('Roblox launcher is stale or not executable: ', entry)! }
  f.clean()!
 }
 release([iterator2])!
 return manifest
}
fn temporary_iter(value string) !string {
 result := call('_ITER', o(value)) or { release([value])!; return err }
 release([value])!
 return result
}

fn stage(state string, mut f Frame) !string {
 named(mut f, 'manifest', call('provenance', o(f.names['android_stage']))!)!
 // Both resolve calls finish before tuple assignment changes either input.
 build := temporary_method(call('Path', o(f.names['build']))!, 'resolve', [], {})!
 android := temporary_method(call('Path', o(f.names['android_stage']))!, 'resolve', [], {}) or { release([build])!; return err }
 named(mut f, 'build', build)!
 named(mut f, 'android_stage', android)!
 staging := named(mut f, 'staging', path(build, 'staging')!)!
 mut overlap := compare('eq', staging, o(android))!
 if !overlap {
  parents := member(android, 'parents')!
  overlap = tested(invoke_owned(resolve('operator.contains')!, [o(parents),o(staging)], {}, [parents])!)!
 }
 if !overlap {
  parents := member(staging, 'parents')!
  overlap = tested(invoke_owned(resolve('operator.contains')!, [o(parents),o(android)], {}, [parents])!)!
 }
 if overlap { return fail('Roblox launcher staging must be separate from the shared Android runtime')! }
 perform_method(build, 'mkdir', [], {'parents': v(ah.Value(true))!, 'exist_ok': v(ah.Value(true))!})!
 return call('_stage_directory', o(state))!
}

fn stage_directory(mut f Frame) !string {
 output := named(mut f, 'output', divided(call('Path', o(f.names['directory']))!, v(ah.Value('staging'))!)!)!
 commands := named(mut f, 'commands', path(output, 'usr/bin')!)!
 perform_method(commands, 'mkdir', [], {'parents': v(ah.Value(true))!})!
 iterator := temporary_iter(global('COMMANDS')!)!
 f.names['private-iterator'] = iterator
 for {
  row := callback('next', {'owner': ah.Value(iterator)})!.object()
  if ah.field(row, 'done') as bool { break }
  name := named(mut f, 'name', ah.field(row, 'value').text())!
  copier := global('shutil.copy2')!
  source := divided(global('SUPPORT')!, o(name))!
  destination := binary('truediv', commands, o(name)) or { release([source,copier])!; return err }
  release([invoke_owned(copier, [o(source),o(destination)], {}, [destination,source])!])!
  perform_temporary_method(binary('truediv', commands, o(name))!, 'chmod', [v(ah.Value(493))!], {})!
  f.clean()!
 }
 release([iterator])!
 receipt := named(mut f, 'receipt', binary('truediv', output, o(global('RECEIPT')!))!)!
 perform_temporary_method(member(receipt, 'parent')!, 'mkdir', [], {'parents': v(ah.Value(true))!})!
 writer := member(receipt, 'write_text')!
 serialized := invoke(global('json.dumps')!, [o(f.names['manifest'])], {'indent': v(ah.Value(2))!})!
 content := added(serialized, v(ah.Value('\n'))!)!
 release([invoke_owned(writer, [o(content)], {}, [content])!])!
 perform('validate_stage', o(output), o(f.names['android_stage']))!
 previous := named(mut f, 'previous', divided(call('Path', o(f.names['directory']))!, v(ah.Value('previous'))!)!)!
 staging := f.names['staging']
 if tested(method(staging, 'exists', [], {})!)! || tested(method(staging, 'is_symlink', [], {})!)! { perform_method(staging, 'rename', [o(previous)], {})! }
 perform('_publish', o(f.pins))!
 return staging
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row, 'arguments').items().map(it.text())
 operation := ah.field(row, 'operation').text()
 current_builtins = ids[1]
 order := match operation {
  'provenance' { ['android_stage','runtime','android_launcher','art','art_manifest','bionic_manifest','atl_manifest','musl_manifest','receipt','manifest','compatibility'] }
  'validate_stage' { ['stage','android_stage','expected','required','actual','path','manifest','error','name','checksum'] }
  else { ['build','android_stage','manifest','staging','directory','output','commands','name','receipt','previous'] }
 }
 mut f := Frame{start: checkpoint()!, pins: ids[0], order: order}
 for key in order {
  exists := tested(call('operator.contains', o(ids[2]),v(ah.Value(key))!)!)!
  if exists { f.named(key, get(ids[2],key)!)! }
 }
 result := execute(operation, ids[2], mut f) or { f.failed(err)!; return err }
 f.pin()!
 // The frontend owns this single ordered dictionary on success and saved error.
 clean_since(f.start, [result])!
 return ah.Value(result)
}

fn execute(operation string, state string, mut f Frame) !string {
 return match operation {
  'provenance' { provenance(state, mut f)! }
  'validate_stage' { validate(state, mut f)! }
  'stage_launchers' { stage(state, mut f)! }
  'stage_directory' { stage_directory(mut f)! }
  else { return error('Unknown Roblox staging operation') }
 }
}

fn add_entry(mut pairs []string, name string, value string) ! {
 pair_ := tuple_([v(ah.Value(name))!, o(value)]) or { release([value])!; return err }
 release([value])!
 pairs << pair_
}
fn provenance_result(mut f Frame) !string {
 mut pairs := []string{}
 defer { for i := pairs.len - 1; i >= 0; i-- { release([pairs[i]]) or {} } }
 add_entry(mut pairs, 'format', literal(ah.Value(1))!)!
 add_entry(mut pairs, 'architecture', literal(ah.Value('aarch64'))!)!
 add_entry(mut pairs, 'execution', literal(ah.Value('native'))!)!
 add_entry(mut pairs, 'page_size', literal(ah.Value(16384))!)!
 add_entry(mut pairs, 'runtime', literal(ah.Value('Android Translation Layer / ART'))!)!
 prefix := global('PREFIX')!
 prefix_value := added(literal(ah.Value('/'))!, o(prefix)) or { release([prefix])!; return err }
 release([prefix])!
 add_entry(mut pairs, 'runtime_prefix', prefix_value)!
 add_entry(mut pairs, 'android_runtime_manifest_sha256', call('digest', o(f.names['receipt']))!)!
 add_entry(mut pairs, 'android_launcher_sha256', call('digest', o(f.names['android_launcher']))!)!
 add_entry(mut pairs, 'android_compatibility_sha256', call('digest', o(f.names['compatibility']))!)!
 add_entry(mut pairs, 'android_libc_sha256', get(f.names['musl_manifest'], 'libc_so_sha256')!)!
 add_entry(mut pairs, 'art_source_commit', get(f.names['art_manifest'], 'source_commit')!)!
 add_entry(mut pairs, 'art_patch_sha256', get(f.names['art_manifest'], 'patch_sha256')!)!
 add_entry(mut pairs, 'bionic_source_commit', get(f.names['bionic_manifest'], 'source_commit')!)!
 add_entry(mut pairs, 'bionic_patch_sha256', get(f.names['bionic_manifest'], 'patch_sha256')!)!
 add_entry(mut pairs, 'atl_source_commit', get(f.names['atl_manifest'], 'source_commit')!)!
 add_entry(mut pairs, 'atl_builder_sha256', get(f.names['atl_manifest'], 'builder_sha256')!)!
 add_entry(mut pairs, 'files', call('_launcher_files')!)!
 add_entry(mut pairs, 'apk_bundled', literal(ah.Value(false))!)!
 return invoke(global('_dict')!, pairs.map(o(it)), {})!
}
