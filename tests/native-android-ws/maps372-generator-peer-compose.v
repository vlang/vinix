// SPDX-License-Identifier: GPL-2.0-or-later
// Derive the qualified370 peer reader without copying its complete audit into Git.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const root = state + '/maps372-generator-peer-composition-2026-10-26'
const reference = repo + '/tests/native-android-ws/maps370-generator-peer-check.v'
const reference_pin = '233ff4e3da04a0f52c7f7f5d5f761a641d028362c77c1973c441f472f62e08c7'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string {
 assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
 return sha256.sum(os.read_bytes(path)!).hex()
}

fn once(text string, before string, after string) !string {
 if text.count(before) != 1 { return error('unique replacement required: ' + before) }
 return text.replace(before, after)
}

fn command(label string, argv []string) ! {
 started := time.utc().str()
 before := hash(argv[0])!
 result := os.exec(argv)
 os.write_file(root + '/' + label + '.log', result.output)!
 os.write_file(root + '/' + label + '.json', json2.encode({
  'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
  'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
  'exit_code': json2.Any(result.exit_code),
  'program_sha256_before': json2.Any(before), 'program_sha256_after': json2.Any(hash(argv[0])!),
  'output_sha256': json2.Any(hash(root + '/' + label + '.log')!),
  'composer_source_sha256': json2.Any(hash(@FILE)!),
  'composer_binary_sha256': json2.Any(hash(os.executable())!),
  'generated_reader_source_sha256': json2.Any(hash(root + '/maps372-generator-peer-check.v')!)
 }, prettify: true) + '\n')!
 assert result.exit_code == 0 && hash(argv[0])! == before, result.output
 print(result.output)
}

fn run() ! {
 assert os.args.len == 1 && os.getwd() == repo && os.real_path(state) == state
 assert !os.exists(root) && !os.is_link(root), 'fresh composition required'
 assert hash(reference)! == reference_pin && hash(compiler)! == compiler_pin
 original := os.read_file(reference)!
 mut text := once(original, "repo + '/tests/native-android-ws/maps370-generate.v'",
  "state + '/maps372-generator-composition-b-2026-10-26/maps372-generate.v'")!
 for before, after in {
  'b3b7cc8a7f669c0b302c1b7d842c88915c655df7173b805339ab8301a8599633': '47741733ef500bc4a62b3fa9f303978ef4987bb1e7b71853e9e0a2a9d24fe121'
  '07563db30ab619e6b3b6440ba454fb27db6e2b559331eef343d316618c42807a': 'ebe3c3683ccab7690cb1f75f8d5e1747aa36cf23b345075a18cc4a6b259d541a'
  'b4a46ea26a62c954470d3617a87cd3bfc593a81b8d4da82d03c4e8eaad78f3a5': '21393930e1c5e1d81f3fa4f6993b604223d9bd11cd329631c4eb310abbf63911'
 } { text = once(text, before, after)! }
 text = text.replace('maps370', 'maps372').replace('MAPS370', 'MAPS372')
 assert !text.contains('maps370') && !text.contains('MAPS370')
 // Only labels, the generated source path and three exact identities may differ.
 for name in ['hash', 'object', 'inventory', 'complete'] {
  marker := '\nfn ' + name + '('
  assert original.count(marker) == 1 && text.count(marker) == 1
  assert original.all_after(marker).all_before('\nfn ') == text.all_after(marker).all_before('\nfn ')
 }
 os.mkdir(root)!
 os.cp(reference, root + '/maps370-generator-peer-check.v')!
 os.cp(@FILE, root + '/composer.v')!
 os.cp(os.executable(), root + '/composer')!
 source := root + '/maps372-generator-peer-check.v'
 program := root + '/reader'
 os.write_file(source, text)!
 os.mkdir(root + '/generated-c')!
 os.setenv('VTMP', root + '/generated-c', true)
 os.setenv('VROOT', '/Users/alex/code/v', true)
 command('compile', [compiler, '-path', '/Users/alex/code/v/vlib', '-nocache', '-cc', '/usr/bin/cc', '-o', program, source])!
 command('readback', [program])!
 assert hash(reference)! == reference_pin && hash(compiler)! == compiler_pin
 assert hash(root + '/maps370-generator-peer-check.v')! == reference_pin
 assert hash(source)! == sha256.sum(text.bytes()).hex()
 assert hash(@FILE)! == hash(root + '/composer.v')! && hash(os.executable())! == hash(root + '/composer')!
 println('MAPS372-GENERATOR-PEER-COMPOSITION-PASS reader_source=' + hash(source)! + ' reader_binary=' + hash(program)!)
}

fn main() {
 $if prod { panic('assertions required') }
 run() or { eprintln(err); exit(1) }
}
