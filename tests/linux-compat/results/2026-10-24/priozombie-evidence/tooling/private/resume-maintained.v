import os

const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const root = '/Users/alex/code/vinix'

fn main() {
 original := os.read_file(area + '/maintained.v')!
 os.write_file(area + '/maintained-second.v', original.replace("'/states/n'", "'/states/m'"))!
 path := root + '/tests/linux-compat/priozombie-evidence.v'
 os.write_file(path, os.read_file(path)!.replace("'maintained-first-'", "'maintained-second-'"))!
 publisher := area + '/publish.v'
 mut source := os.read_file(publisher)!.replace('["n", "maintained"]', '["m", "maintained"]')
 source = source.replace('for name in ["compile-first-", "compile-second-", "linux-second-"]', 'for name in ["compile-first-", "compile-second-", "linux-second-", "n"]')
 os.write_file(publisher, source)!
 for suffix in ['arm', 'x86'] {
  state := area + '/states/maintained-first-' + suffix + '-interruption.json'
  os.write_file(state, '{"state":"interrupted before controller completion; no exit status captured","artifacts":"n' + suffix + '"}\n')!
 }
}
