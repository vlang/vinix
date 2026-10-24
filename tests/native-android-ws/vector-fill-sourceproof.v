// SPDX-License-Identifier: GPL-2.0-or-later
// Bind Maps location-control XML and its owner classes to the signed APK.
import crypto.sha256
import json2
import os

fn hash(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn word(data []u8, at int) int { return int(u32(data[at]) | u32(data[at+1]) << 8 | u32(data[at+2]) << 16 | u32(data[at+3]) << 24) }
fn dex_type(data []u8, index int) string {
 mut at := word(data, word(data, 60) + word(data, word(data, 68) + index * 4) * 4)
 for data[at] & 128 != 0 { at++ }
 at++
 mut end := at
 for end < data.len && data[end] != 0 { end++ }
 return data[at..end].bytestr()
}
fn checked(args []string) string {
 r := os.exec(args)
 assert r.exit_code == 0, r.output
 return r.output
}
fn main() {
 $if prod { panic('assertions required') }
 assert os.args.len == 2, 'OUTPUT'
 out := os.abs_path(os.args[1])
 assert !os.exists(out)
 os.mkdir_all(out + '/dex')!
 os.cp('tests/native-android-ws/vector-fill-sourceproof.v', out + '/author.v')!
 apk := os.abs_path('build/android-maps/GoogleMaps.apk')
 assert hash(apk) == '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
 aapt := os.abs_path('build/android-native-ws/aapt2')
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 tools_root := os.abs_path('build/android-framework/tools')
 tools := tools_root + '/*'
 mut tool_pins := map[string]string{}
 for path in [aapt, java] { tool_pins[path] = hash(path) }
 mut classpath := os.ls(tools_root)!.filter(it.ends_with('.jar'))
 classpath.sort()
 assert classpath.len > 0
 for name in classpath { tool_pins[tools_root + '/' + name] = hash(tools_root + '/' + name) }
 mut commands := [][]string{}
 for xml in ['m5z', 'TF3'] {
  args := [aapt, 'dump', 'xmltree', '--file', 'res/' + xml + '.xml', apk]
  commands << args
  os.write_file(out + '/' + xml + '-xmltree.txt', checked(args))!
 }
 args := [aapt, 'dump', 'resources', apk]
 commands << args
 lines := checked(args).split_into_lines()
 mut excerpts := []string{}
 for i, line in lines {
  if line.ends_with('drawable/center_location') || line.ends_with('drawable/location_not_granted') {
   for j in i .. int_min(i + 4, lines.len) { excerpts << lines[j] }
  }
 }
 assert excerpts.join('\n').contains('res/m5z.xml')
 assert excerpts.join('\n').contains('res/TF3.xml')
 os.write_file(out + '/resource-excerpts.txt', excerpts.join('\n') + '\n')!
 mut classes := map[string]string{}
 for name in os.ls('build/android-maps/dex-refs')! {
  if !name.ends_with('.dex') { continue }
  path := 'build/android-maps/dex-refs/' + name
  data := os.read_bytes(path)!
  mut found := []string{}
  for i in 0 .. word(data, 96) {
   class_name := dex_type(data, word(data, word(data, 100) + i * 32))
   if class_name in ['Lamnv;', 'Lpaw;', 'Lpam;'] { found << class_name }
  }
  if found.len == 0 { continue }
  extract := ['unzip', '-q', '-j', apk, name, '-d', out + '/dex']
  commands << extract
  checked(extract)
  assert hash(path) == hash(out + '/dex/' + name)
  disassemble := [java, '-cp', tools, 'org.jf.baksmali.Main', 'disassemble', '--classes', found.join(','), '-o', out + '/smali', out + '/dex/' + name]
  commands << disassemble
  checked(disassemble)
  for class_name in found { classes[class_name] = name }
 }
 assert classes.len == 3
 for name in ['amnv', 'paw', 'pam'] { assert hash(out + '/smali/' + name + '.smali') == hash('build/android-maps/inspect/' + name + '.smali') }
 assert hash(apk) == '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
 mut after_classpath := os.ls(tools_root)!.filter(it.ends_with('.jar'))
 after_classpath.sort()
 assert after_classpath == classpath
 for path, pin in tool_pins { assert hash(path) == pin, path }
 os.write_file(out + '/commands.json', json2.encode(commands, prettify: true) + '\n')!
 os.write_file(out + '/inputs.json', json2.encode({'apk': apk, 'apk_sha256': hash(apk), 'aapt2_sha256': hash(aapt), 'java_sha256': hash(java)}, prettify: true) + '\n')!
 os.write_file(out + '/tools.json', json2.encode(tool_pins, prettify: true) + '\n')!
 os.write_file(out + '/classes.json', json2.encode(classes, prettify: true) + '\n')!
 mut pins := map[string]string{}
 for path in os.walk_ext(out, '') { if os.is_file(path) { pins[path.all_after(out + '/')] = hash(path) } }
 os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
 println(out + ' ' + hash(out + '/sha256.json'))
}

