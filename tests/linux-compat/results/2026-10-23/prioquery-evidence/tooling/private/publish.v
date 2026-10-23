import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const root = '/Users/alex/code/vinix'
const destination = root + '/tests/linux-compat/results/2026-10-23/prioquery-evidence'

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
  mut copier := os.new_process('/bin/cp')
  copier.set_args(['-c', source, target])
  copier.set_redirect_stdio_merged()
  copier.run()
  output := copier.stdout_slurp()
  copier.wait()
  code := copier.code
  copier.close()
  if code != 0 { return error('Clone failed: ' + output) }
  manifest.canonical[pin] = relative
 }
 if digest(target)! != pin { return error('Copy changed: ' + source) }
 manifest.files[relative] = pin
 manifest.origins[source] = relative
}

fn directory(source string, relative string, mut manifest Manifest) ! {
 for path in os.walk_ext(source, '') {
  info := os.stat(path)!
  if info.get_filetype() != .regular { continue }
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
 assert !os.exists(destination), "Fresh destination required"
 mut manifest := Manifest{}
 manifest.omitted = json2.decode[map[string]string](os.read_file(area + "/removed-media.json")!)!
 for suffix in ["arm", "x86"] {
  directory(area + "/states/compile-second-" + suffix, suffix + "/compile", mut manifest)!
  for pair in [["baseline-first-", "baseline"], ["linux-first-", "reference"], ["candidate-second-", "native"]] {
   ending := if pair[1] == "reference" { "" } else { "-guest" }
   directory(area + "/states/" + pair[0] + suffix + ending, suffix + "/" + pair[1], mut manifest)!
  }
  directory(area + "/states/kernel-second-" + suffix + "-prod", suffix + "/build", mut manifest)!
  maintained := if suffix == "arm" { "m3arm" } else { "m4x86" }
  directory(area + "/states/" + maintained, suffix + "/maintained", mut manifest)!
  if suffix == "x86" { directory(area + "/states/m3x86", "attempts/maintained-third-x86", mut manifest)! }
  for name in ["compile-first-" + suffix, "candidate-first-" + suffix + "-guest", "kernel-first-" + suffix + "-prod", "maintained-first-" + suffix, "maintained-second-" + suffix] {
   path := area + "/states/" + name
   if os.is_dir(path) { directory(path, "attempts/" + name, mut manifest)! }
  }
 }
 directory(area + "/frozen-second", "source/fixture", mut manifest)!
 directory(area + "/frozen-first", "attempts/frozen-first", mut manifest)!
 directory(area + "/first-source", "attempts/first-source", mut manifest)!
 directory(area + "/source/kernel", "source/kernel", mut manifest)!
 for name in ["threadnice", "niceabi", "niceadmit", "attrnice", "groupabi", "grouptid"] {
  copy_file(root + "/tests/linux-compat/" + name + "fixture/core.v", "source/fixture/" + name + "fixture/core.v", mut manifest)!
 }
 copy_file(area + "/source.diff", "source/change.diff", mut manifest)!
 copy_file(area + "/prepared-source-inputs.json", "source/identity.json", mut manifest)!
 copy_file(area + "/first-source.diff", "attempts/first-source.diff", mut manifest)!
 copy_file(area + "/first-prepared-source-inputs.json", "attempts/first-source-identity.json", mut manifest)!
 for name in ["generated-review.json", "generated-review-arm.c.txt", "generated-review-x86.c.txt"] {
  copy_file(area + "/" + name, "review/" + name, mut manifest)!
 }
 for name in ["prioquery-reference.v", "prioquery-evidence.v", "run.v"] {
  copy_file(root + "/tests/linux-compat/" + name, "tooling/" + name, mut manifest)!
 }
 for name in ["compile.v", "reference.v", "native.v", "build-kernels.v", "first-build-kernels.v", "integrate.v", "review-generated.v", "maintained-native.v", "maintained-second.v", "maintained-third.v", "maintained-fourth.v", "prepare-retry.v", "arm-cc.v", "arm-cc-third.v", "publish.v", "prepare-publisher.v", "prepare-docs.v", "setup-kernels.v", "setup-maintained-second.v", "setup-maintained-third.v", "prepare-probe.v", "revise.v", "freeze.v", "prune-media.v", "prune-completed.v", "removed-media.json", "prune-objects.v", "removed-objects.json"] {
  copy_file(area + "/" + name, "tooling/private/" + name, mut manifest)!
 }
 copy_file(area + "/report.md", "README.md", mut manifest)!
 copy_file(area + "/linux-v6.12-sys.c", "reference/linux-v6.12-sys.c", mut manifest)!
 for name in os.ls(area + "/states")! {
  path := area + "/states/" + name
  if os.is_file(path) && (path.ends_with(".log") || path.ends_with(".status") || path.ends_with(".command.json")) {
   copy_file(path, "attempts/" + name, mut manifest)!
  }
 }
 for suffix in ["arm", "x86"] {
  path := destination + "/" + suffix
  fields(path + "/build/receipt.json", ["inputs_before", "inputs_after", "outputs"], mut manifest)!
  fields(path + "/compile/receipt.json", ["inputs", "outputs"], mut manifest)!
  for kind in ["baseline", "native"] { fields(path + "/" + kind + "/receipt.json", ["inputs"], mut manifest)! }
  for name in ["reference/inputs.json", "maintained/controller-inputs.json"] {
   pins(json2.decode[map[string]string](os.read_file(path + "/" + name)!)!, mut manifest)!
  }
  object := json2.decode[map[string]json2.Any](os.read_file(path + "/maintained/receipt.json")!)!
  results := object["results"] or { return error("Missing maintained results") }
  for item in results.as_array() {
   record := item.as_map()
   inputs := record["source_inputs"] or { return error("Missing fixture source inputs") }
   pins(json2.decode[map[string]string](json2.encode(inputs))!, mut manifest)!
  }
 }
 os.write_file(destination + "/manifest.json", json2.encode(manifest, prettify: true) + "\n")!
 println("Published " + manifest.files.len.str() + " artifacts; " + manifest.omitted.len.str() + " external pins")
}

fn main() { publish() or { eprintln(err); exit(1) } }
