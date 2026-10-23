import os
import crypto.sha256
import json2

fn run(arguments []string) !string {
 r := os.exec(arguments)
 if r.exit_code != 0 { return error(r.output) }
 return r.output
}

fn main() {
 b := 'build/android-maps/'
 task := b + 'stream238/'
 helper := os.read_file(task + 'pipeline.v.txt')!
 prototype := 'import os\nimport crypto.sha256\n' + helper + os.read_file(task + 'prototype.v.txt')!
 os.write_file(task + 'prototype.v', prototype)!
 source := os.read_file(b + 'suite-low-disk.v')!
 old := "\tarchive := output + '/module.tar'\n\tchecked(['tar', '--format=ustar', '-cf', archive, '-C', module_root, '.'])!\n\tchecked(['mcopy', '-o', '-i', settings['boot_image']!.str(), archive, '::/boot/qemu-runtime.tar'])!\n\tos.rm(archive)!"
 assert source.count(old) == 1
 replacement := "\tstream_module(module_root, settings['boot_image']!.str())!"
 frozen := source.replace(old, replacement) + '\n' + helper
 assert frozen.all_before('\n#include <spawn.h>').replace(replacement, old) == source
 os.write_file(b + 'suite238-stream.v', frozen)!
 for name in ['prototype', '../suite238-stream'] {
  command := ['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-path', '@vlib|build-support/android', '-o', task + name, task + name + '.v']
  log := run(command)!
  os.write_file(task + os.base(name) + '-build.log', log)!
 }
 mut hashes := map[string]string{}
 for path in [b + 'suite159', b + 'suite-low-disk.v', b + 'suite238-stream.v', b + 'suite238-stream', task + 'pipeline.v.txt', task + 'prototype.v.txt', task + 'prototype.v', task + 'prototype', task + 'prepare.v'] {
  hashes[path] = sha256.sum(os.read_bytes(path)!).hex()
 }
 os.write_file(task + 'sha256.json', json2.encode(hashes, prettify: true) + '\n')!
 diff := os.exec(['diff', '-u', b + 'suite-low-disk.v', b + 'suite238-stream.v'])
 assert diff.exit_code == 1
 os.write_file(task + 'suite.diff', diff.output)!
 println('STREAM238 BUILD PASS')
}
