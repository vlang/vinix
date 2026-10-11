import crypto.sha256
import json2
import os

struct Package {
 name string
 version string
 dependencies []string
 provides []string
 url string
}

fn execute(argv []string) ! {
 mut process := os.new_process(argv[0])
 process.set_args(argv[1..])
 process.run()
 process.wait()
 defer { process.close() }
 if process.code != 0 { return error('input acquisition failed: ' + argv.str()) }
}

fn copy_tree(source string, destination string) ! {
 if os.is_link(source) { os.symlink(os.readlink(source)!, destination)!; return }
 mode := int(os.stat(source)!.mode & 0o7777)
 if os.is_dir(source) {
  os.mkdir_all(destination)!
  for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name)! }
 } else if os.is_file(source) { os.cp(source, destination)! }
 else { return error('unsupported root input: ' + source) }
 os.chmod(destination, mode)!
}

fn dep_name(value string) string {
 for index, ch in value {
  if ch in [`=`, `>`, `<`, `~`] { return value[..index] }
 }
 return value
}

fn main() {
 assert os.args.len >= 5 && os.args[1] in ['aarch64', 'x86_64']
 arch := os.args[1]
 base := os.real_path(os.args[2])
 output := os.abs_path(os.args[3])
 assert os.is_dir(base) && !os.exists(output) && !output.starts_with(base + '/')
 copy_tree(base, output + '/root')!
 mut inputs := map[string]string{}
 inputs['stager_source'] = sha256.sum(os.read_bytes(@FILE)!).hex()
 mut packages := map[string]Package{}
 mut providers := map[string]string{}
 mut ambiguous := map[string]bool{}
 for repository in ['main', 'community'] {
  url := 'https://dl-cdn.alpinelinux.org/alpine/v3.21/' + repository + '/' + arch + '/'
  cache := output + '/' + repository
  os.mkdir_all(cache)!
  archive := cache + '/APKINDEX.tar.gz'
  execute(['curl', '--fail', '--location', '--silent', '--show-error', '--max-time', '90', '-o', archive, url + 'APKINDEX.tar.gz'])!
  inputs[url + 'APKINDEX.tar.gz'] = sha256.sum(os.read_bytes(archive)!).hex()
  execute(['tar', '-xzf', archive, '-C', cache])!
  for row in os.read_file(cache + '/APKINDEX')!.split('\n\n') {
   mut fields := map[string]string{}
   for line in row.split_into_lines() {
    if line.len >= 2 && line[1] == `:` { fields[line[..1]] = line[2..] }
   }
   if fields['P'] == '' { continue }
   name := fields['P']
   if name in packages {
    if packages[name].version != fields['V'] { ambiguous[name] = true }
    continue
   }
   packages[name] = Package{name, fields['V'], fields['D'].split(' ').filter(it != ''), fields['p'].split(' ').filter(it != ''), url}
   for provider in packages[name].provides { providers[dep_name(provider)] = name }
  }
 }
 mut pending := os.args[4..].clone()
 mut selected := map[string]Package{}
 for pending.len > 0 {
  dependency := pending.pop()
  if dependency.starts_with('!') { continue }
  name := dep_name(dependency)
  provider := if name in packages { name } else { providers[name] or { panic('missing input: ' + dependency) } }
  assert provider !in ambiguous, 'selected input requires APK version resolution: ' + provider
  if provider in selected { continue }
  package := packages[provider]
  selected[provider] = package
  pending << package.dependencies
 }
 mut names := selected.keys()
 names.sort()
 os.mkdir_all(output + '/archives')!
 for name in names {
  package := selected[name]
  file := name + '-' + package.version + '.apk'
  archive := output + '/archives/' + file
  execute(['curl', '--fail', '--location', '--silent', '--show-error', '--max-time', '90', '-o', archive, package.url + file])!
  inputs[package.url + file] = sha256.sum(os.read_bytes(archive)!).hex()
  // Acquisition for diagnosis only: APK signatures and installation scripts
  // are qualified separately by real guest package transactions.
  execute(['tar', '-xzf', archive, '-C', output + '/root'])!
  println(name + ' ' + package.version)
 }
 root := output + '/root'
 for name in ['lib/ld-musl-' + arch + '.so.1', 'lib/libc.musl-' + arch + '.so.1'] {
  if os.exists(root + '/' + name) || os.is_link(root + '/' + name) { os.rm(root + '/' + name)! }
  if os.exists(base + '/' + name) { os.cp(base + '/' + name, root + '/' + name)! }
 }
 for directory in ['lib', 'usr/lib'] {
  for path in os.walk_ext(root + '/' + directory, '') {
   if !os.is_link(path) || !os.file_name(path).contains('.so') { continue }
   mut target := path
   mut hops := 0
   for os.is_link(target) {
    hops++
    assert hops <= 40
    link := os.readlink(target)!
    target = os.norm_path(if link.starts_with('/') { root + link } else { os.dir(target) + '/' + link })
    assert target.starts_with(root + '/')
   }
   contents := os.read_bytes(target)!
   mode := int(os.stat(target)!.mode & 0o7777)
   os.rm(path)!
   os.write_file_array(path, contents)!
   os.chmod(path, mode)!
  }
 }
 os.write_file(output + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
 println('Runtime inputs staged; extraction is not an installation receipt')
}
