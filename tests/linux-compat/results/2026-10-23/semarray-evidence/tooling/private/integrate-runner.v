import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'

fn main() {
 path := root + '/tests/linux-compat/run.v'
 text := os.read_file(path)!
 assert !text.contains("name == 'semarray'")
 updated := text.replace('semabi,semword,sempid', 'semabi,semword,sempid,semarray')
  .replace("'semabi', 'semword', 'sempid'", "'semabi', 'semword', 'sempid', 'semarray'")
  .replace("\t\t\t} else if name == 'sysrq' {", "\t\t\t} else if name == 'semarray' {\n\t\t\t\t[marker, 'LINUX SEMARRAY SUMMARY: checks=457 failures=0']\n\t\t\t} else if name == 'sysrq' {")
 assert updated != text
 os.write_file(path, updated)!
 os.write_file(area + '/maintained-native.v', os.read_file(old + '/maintained-native.v')!
  .replace(old, area).replace("'/states/spid1-'", "'/states/sa1-'")
  .replace("root + '/tests/linux-compat/sempidfixture/core.v',", "root + '/tests/linux-compat/sempidfixture/core.v', root + '/tests/linux-compat/semarrayfixture/core.v',")
  .replace("'sempid,semword,semabi'", "'semarray,sempid,semword,semabi'"))!
}
