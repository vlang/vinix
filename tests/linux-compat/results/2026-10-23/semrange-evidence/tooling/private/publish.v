import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'
const destination = root + '/tests/linux-compat/results/2026-10-23/semrange-evidence'

struct Manifest {
mut:
 files map[string]string
 origins map[string]string
 omitted map[string]string
 canonical map[string]string @[skip]
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn copy_file(source string, relative string, mut manifest Manifest) ! {
 target := destination + '/' + relative
 os.mkdir_all(os.dir(target))!
 pin := digest(source)!
 duplicate := manifest.canonical[pin] or { '' }
 if duplicate != '' {
  depth := if os.dir(relative) == '.' { 0 } else { os.dir(relative).split('/').len }
  os.symlink('../'.repeat(depth) + duplicate, target)!
 } else {
  os.cp(source, target)!
  manifest.canonical[pin] = relative
 }
 if digest(target)! != pin { return error('Copy changed: ' + source) }
 manifest.files[relative] = pin
 manifest.origins[source] = relative
}

fn directory(source string, relative string, mut manifest Manifest) ! {
 for path in os.walk_ext(source, '') {
  if !os.is_file(path) { continue }
  name := path[source.len + 1..]
  if name.ends_with('.iso') || name.ends_with('initramfs.tar') || name.ends_with('initramfs.cpio')
    || name == 'linux' || name.ends_with('.qcow2') || name.ends_with('.fd') || name.contains('/limine/') {
   manifest.omitted[path] = digest(path)!
   continue
  }
  copy_file(path, relative + '/' + name, mut manifest)!
 }
}

fn pins(values map[string]string, mut manifest Manifest) ! {
 for origin, pin in values {
  if relative := manifest.origins[origin] {
   if manifest.files[relative] != pin { return error('Retained pin conflicts: ' + origin) }
  } else {
   if old := manifest.omitted[origin] { if old != pin { return error('Conflicting external pin: ' + origin) } }
   manifest.omitted[origin] = pin
  }
 }
}

fn fields(path string, names []string, mut manifest Manifest) ! {
 object := json2.decode[map[string]json2.Any](os.read_file(path)!)!
 for name in names {
  value := object[name] or { return error('Missing field: ' + name) }
  pins(json2.decode[map[string]string](json2.encode(value))!, mut manifest)!
 }
}

fn publish() ! {
 assert !os.exists(destination), 'Fresh destination required'
 mut manifest := Manifest{}
 for suffix in ['arm', 'x86'] {
  directory(area + '/states/compile-second-' + suffix, suffix + '/compile', mut manifest)!
  for pair in [['old-first-', 'baseline'], ['linux-first-', 'reference'], ['new-first-', 'native']] {
   directory(area + '/states/' + pair[0] + suffix, suffix + '/' + pair[1], mut manifest)!
  }
  directory(area + '/states/kernel-first-' + suffix + '-prod', suffix + '/build', mut manifest)!
  directory(previous + '/states/sr1-' + suffix, suffix + '/maintained', mut manifest)!
  directory(area + '/states/compile-first-' + suffix, 'attempts/compile-first-' + suffix, mut manifest)!
 }
 directory(area + '/frozen-second', 'source/fixture', mut manifest)!
 directory(area + '/frozen-first', 'attempts/frozen-first', mut manifest)!
 for name in ['semabi', 'semword', 'sempid', 'semarray'] {
  copy_file(root + '/tests/linux-compat/' + name + 'fixture/core.v', 'source/fixture/' + name + 'fixture/core.v', mut manifest)!
 }
 copy_file(area + '/sysvsem-candidate.v', 'source/sysvsem.v', mut manifest)!
 copy_file(area + '/source.diff', 'source/change.diff', mut manifest)!
 copy_file(area + '/prepared-source-inputs.json', 'source/identity.json', mut manifest)!
 for name in ['generated-review.json', 'generated-review-arm.c.txt', 'generated-review-x86.c.txt'] {
  copy_file(area + '/' + name, 'review/' + name, mut manifest)!
 }
 for name in ['semrange-reference.v', 'semrange-evidence.v', 'run.v'] {
  copy_file(root + '/tests/linux-compat/' + name, 'tooling/' + name, mut manifest)!
 }
 for name in ['compile.v', 'native.v', 'build-kernels.v', 'integrate-runner.v', 'finish-tools.v',
  'review-generated.v', 'maintained-native.v', 'publish.v', 'setup.v', 'removed-prior-media-pins.json'] {
  copy_file(area + '/' + name, 'tooling/private/' + name, mut manifest)!
 }
 copy_file(area + '/report.md', 'README.md', mut manifest)!
 copy_file(area + '/linux-v6.12-sem.c', 'reference/linux-v6.12-sem.c', mut manifest)!
 for name in os.ls(area + '/states')! {
  path := area + '/states/' + name
  if os.is_file(path) && (path.ends_with('.log') || path.ends_with('.status') || path.ends_with('.command.json') || path.ends_with('.recovery.json')) {
   copy_file(path, 'attempts/' + os.file_name(path), mut manifest)!
  }
 }
 for suffix in ['arm', 'x86'] {
  path := destination + '/' + suffix
  fields(path + '/build/receipt.json', ['inputs_before', 'inputs_after', 'outputs'], mut manifest)!
  fields(path + '/compile/receipt.json', ['inputs', 'outputs'], mut manifest)!
  for kind in ['baseline', 'native'] { fields(path + '/' + kind + '/receipt.json', ['inputs'], mut manifest)! }
  for name in ['reference/inputs.json', 'maintained/controller-inputs.json'] {
   pins(json2.decode[map[string]string](os.read_file(path + '/' + name)!)!, mut manifest)!
  }
  object := json2.decode[map[string]json2.Any](os.read_file(path + '/maintained/receipt.json')!)!
  results := object['results'] or { return error('Missing maintained results') }
  for item in results.as_array() {
   record := item.as_map()
   inputs := record['source_inputs'] or { return error('Missing fixture source inputs') }
   pins(json2.decode[map[string]string](json2.encode(inputs))!, mut manifest)!
  }
 }
 os.write_file(destination + '/manifest.json', json2.encode(manifest, prettify: true) + '\n')!
 println('Published ' + manifest.files.len.str() + ' artifacts; ' + manifest.omitted.len.str() + ' external pins')
}

fn main() {
 publish() or { eprintln(err); exit(1) }
}
