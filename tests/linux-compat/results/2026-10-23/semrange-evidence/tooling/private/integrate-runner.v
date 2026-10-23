import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'

fn main() {
 path := root + '/tests/linux-compat/run.v'
 text := os.read_file(path)!
 assert !text.contains("name == 'semrange'")
 updated := text.replace('semabi,semword,sempid,semarray', 'semabi,semword,sempid,semarray,semrange')
  .replace("'semabi', 'semword', 'sempid', 'semarray'", "'semabi', 'semword', 'sempid', 'semarray', 'semrange'")
  .replace("\t\t\t} else if name == 'sysrq' {", "\t\t\t} else if name == 'semrange' {\n\t\t\t\t[marker, 'LINUX SEMRANGE SUMMARY: checks=4200 failures=0']\n\t\t\t} else if name == 'sysrq' {")
 assert updated != text
 os.write_file(path, updated)!
 os.write_file(area + '/maintained-native.v', os.read_file(old + '/maintained-native.v')!
  .replace(old, area).replace("'/states/sa1-'", "'/states/sr1-'")
  .replace("root + '/tests/linux-compat/semarrayfixture/core.v',", "root + '/tests/linux-compat/semarrayfixture/core.v', root + '/tests/linux-compat/semrangefixture/core.v',")
  .replace("'semarray,sempid,semword,semabi'", "'semrange,semarray,sempid,semword,semabi'"))!
}
