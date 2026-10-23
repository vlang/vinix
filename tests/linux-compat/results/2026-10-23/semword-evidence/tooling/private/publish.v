import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semword-20261023'
const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'
const destination = root + '/tests/linux-compat/results/2026-10-23/semword-evidence'

struct Manifest {
mut:
 files map[string]string
 origins map[string]string
 omitted map[string]string
}

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn copy_file(source string, relative string, mut manifest Manifest) ! {
 target := destination + '/' + relative
 os.mkdir_all(os.dir(target))!
 os.cp(source, target)!
 pin := digest(source)!
 if digest(target)! != pin { return error('Copy changed: ' + source) }
 manifest.files[relative] = pin
 manifest.origins[source] = relative
}

fn directory(source string, relative string, mut manifest Manifest) ! {
 for path in os.walk_ext(source, '') {
  if !os.is_file(path) { continue }
  name := path[source.len + 1..]
  if name.ends_with('.iso') || name.ends_with('initramfs.tar') || name.ends_with('initramfs.cpio')
    || name == 'linux' || name.ends_with('.qcow2') || name.contains('/limine/') {
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
  directory(area + '/states/compile-probe4-' + suffix + '-' + suffix, suffix + '/compile', mut manifest)!
  for pair in [['baseline2-', 'baseline'], ['linux2-', 'reference'], ['native1-', 'native']] {
   directory(area + '/states/' + pair[0] + suffix, suffix + '/' + pair[1], mut manifest)!
  }
  directory(area + '/states/kernel-native1-' + suffix + '-prod', suffix + '/build', mut manifest)!
  directory(previous + '/states/sw1-' + suffix, suffix + '/maintained', mut manifest)!
  // Preserve exploratory 240-case probes and unsuccessful compilation attempts.
  for prefix in ['baseline1-', 'linux1-', 'compile-probe2-', 'compile-probe3-'] {
   state := area + '/states/' + prefix + suffix + if prefix.starts_with('compile') { '-' + suffix } else { '' }
   if os.is_dir(state) { directory(state, 'attempts/' + os.file_name(state), mut manifest)! }
  }
 }
 directory(area + '/states/compile-probe1-x86', 'attempts/compile-probe1-x86', mut manifest)!
 directory(area + '/frozen-probe4-arm', 'source/fixture', mut manifest)!
 copy_file(root + '/tests/linux-compat/semabifixture/core.v', 'source/fixture/semabifixture/core.v', mut manifest)!
 copy_file(area + '/sysvsem-candidate.v', 'source/sysvsem.v', mut manifest)!
 copy_file(area + '/source.diff', 'source/change.diff', mut manifest)!
 copy_file(area + '/prepared-source-inputs.json', 'source/identity.json', mut manifest)!
 for name in ['generated-review.json', 'generated-review-arm.c.txt', 'generated-review-x86.c.txt'] {
  copy_file(area + '/' + name, 'review/' + name, mut manifest)!
 }
 for name in ['semword-reference.v', 'semword-evidence.v', 'run.v'] {
  copy_file(root + '/tests/linux-compat/' + name, 'tooling/' + name, mut manifest)!
 }
 for name in ['compile.v', 'native.v', 'build-kernels.v', 'prepare-build.v', 'continue-tools.v',
  'review-generated.v', 'maintained-native.v', 'publish.v'] {
  copy_file(area + '/' + name, 'tooling/private/' + name, mut manifest)!
 }
 copy_file(area + '/report.md', 'README.md', mut manifest)!
 for path in os.walk_ext(area, '') {
  if os.dir(path) == area && (path.ends_with('.log') || path.ends_with('.status') || path.ends_with('.command.json')) {
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
