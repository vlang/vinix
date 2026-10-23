import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semword-20261023'

fn main() {
 path := root + '/tests/linux-compat/run.v'
 text := os.read_file(path)!
 assert !text.contains("name == 'sempid'")
 updated := text.replace('semwait,semabi,semword', 'semwait,semabi,semword,sempid')
  .replace("'semwait', 'semabi', 'semword'", "'semwait', 'semabi', 'semword', 'sempid'")
  .replace("\t\t\t} else if name == 'sysrq' {", "\t\t\t} else if name == 'sempid' {\n\t\t\t\t[marker, 'LINUX SEMPID SUMMARY: checks=261 failures=0']\n\t\t\t} else if name == 'sysrq' {")
 assert updated != text
 os.write_file(path, updated)!
 os.write_file(area + '/maintained-native.v', os.read_file(old + '/maintained-native.v')!
  .replace(old, area).replace("'/states/sw1-'", "'/states/spid1-'")
  .replace("'/states/kernel-native1-'", "'/states/kernel-first-'")
  .replace("root + '/tests/linux-compat/semwordfixture/core.v',", "root + '/tests/linux-compat/semwordfixture/core.v', root + '/tests/linux-compat/sempidfixture/core.v',")
  .replace("'semword,semabi'", "'sempid,semword,semabi'"))!
}
