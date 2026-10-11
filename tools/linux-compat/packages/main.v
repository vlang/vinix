// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct Package {
 name string
 version string
 dependencies []string
 provides []string
}

fn run(argv []string) ! {
 mut child := os.new_process(argv[0])
 child.set_args(argv[1..])
 child.run()
 child.wait()
 defer { child.close() }
 if child.code != 0 { return error('command failed: ' + argv.str()) }
}

fn copy_tree(source string, destination string) ! {
 if os.is_link(source) {
  os.symlink(os.readlink(source)!, destination)!
 } else if os.is_dir(source) {
  os.mkdir_all(destination)!
  for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name)! }
  os.chmod(destination, int(os.stat(source)!.mode & 0o7777))!
 } else if os.is_file(source) {
  os.cp(source, destination)!
  os.chmod(destination, int(os.stat(source)!.mode & 0o7777))!
 } else { return error('unsupported input node: ' + source) }
}

fn dep_name(value string) string {
 for index, ch in value {
  if ch in [`=`, `>`, `<`, `~`] { return value[..index] }
 }
 return value
}

fn main() {
 if os.args.len != 4 || os.args[1] !in ['aarch64', 'x86_64'] {
  eprintln('Usage: packages ARCH PREPARED-BASE-ROOT FRESH-OUTPUT')
  exit(2)
 }
 arch := os.args[1]
 base := os.real_path(os.args[2])
 output := os.abs_path(os.args[3])
 if !os.is_dir(base) || os.exists(output) || output.starts_with(base + '/') {
  eprintln('base root must exist and output must be fresh and outside it')
  exit(2)
 }
 copy_tree(base, output + '/root')!
 mut inputs := map[string]string{}
 for version in ['v3.20', 'v3.21'] {
  url := 'https://dl-cdn.alpinelinux.org/alpine/' + version + '/main/' + arch + '/'
  mirror := output + '/root/usr/share/linux-compat-repos/' + version + '/' + arch
  os.mkdir_all(mirror)!
  index := mirror + '/APKINDEX.tar.gz'
  run(['curl', '--fail', '--location', '--silent', '--show-error', '--max-time', '90', '-o', index, url + 'APKINDEX.tar.gz'])!
  index_bytes := os.read_bytes(index)!
  inputs[url + 'APKINDEX.tar.gz'] = sha256.sum(index_bytes).hex()
  expanded := output + '/index-' + version
  os.mkdir_all(expanded)!
  run(['tar', '-xzf', index, '-C', expanded])!
  mut packages := map[string]Package{}
  mut providers := map[string]string{}
  for row in os.read_file(expanded + '/APKINDEX')!.split('\n\n') {
   mut fields := map[string]string{}
   for line in row.split_into_lines() {
    if line.len >= 2 && line[1] == `:` { fields[line[..1]] = line[2..] }
   }
   if fields['P'] == '' { continue }
   name := fields['P']
   packages[name] = Package{name, fields['V'], fields['D'].split(' ').filter(it != ''), fields['p'].split(' ').filter(it != '')}
   for provider in packages[name].provides { providers[dep_name(provider)] = name }
  }
  // Acquisition only. APK performs the real dependency resolution and
  // signature validation inside Vinix, against these unchanged signed indexes.
  mut pending := if version == 'v3.21' { ['sqlite', 'apk-tools', 'alpine-keys'] } else { ['sqlite'] }
  mut selected := map[string]Package{}
  for pending.len > 0 {
   dependency := pending.pop()
   if dependency.starts_with('!') { continue }
   name := dep_name(dependency)
   provider := if name in packages { name } else { providers[name] or { panic('missing package input: ' + dependency) } }
   if provider in selected { continue }
   package := packages[provider]
   selected[provider] = package
   pending << package.dependencies
  }
  mut names := selected.keys()
  names.sort()
  for name in names {
   package := selected[name]
   archive := mirror + '/' + name + '-' + package.version + '.apk'
   run(['curl', '--fail', '--location', '--silent', '--show-error', '--max-time', '90', '-o', archive, url + os.file_name(archive)])!
   bytes := os.read_bytes(archive)!
   inputs[url + os.file_name(archive)] = sha256.sum(bytes).hex()
   // The boot root needs real APK and its libraries, but sqlite is installed
   // into the separate disk root by the guest transaction, never extracted there.
   if version == 'v3.21' && name != 'sqlite' {
    run(['tar', '-xzf', archive, '-C', output + '/root'])!
   }
   println(version + ': ' + name + ' ' + package.version)
  }
  os.write_file(output + '/sqlite-' + version + '.txt', packages['sqlite'].version + '\n')!
  os.write_file(os.dir(mirror) + '/sqlite.version', packages['sqlite'].version + '\n')!
 }
 root := output + '/root'
 // Restore the prepared Vinix interpreter in the boot root. The installed
 // disk root will use the unmodified musl package selected by APK.
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
   content := os.read_bytes(target)!
   mode := int(os.stat(target)!.mode & 0o7777)
   os.rm(path)!
   os.write_file_array(path, content)!
   os.chmod(path, mode)!
  }
 }
 os.cp(os.real_path(os.dir(@FILE) + '/../../../build-support/vinix-pkg'), root + '/usr/bin/pkg')!
 os.chmod(root + '/usr/bin/pkg', 0o755)!
 os.write_file(output + '/packages.json', json2.encode(inputs, prettify: true) + '\n')!
}
