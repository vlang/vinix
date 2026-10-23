import os
const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
fn main() {
 path := root + '/tests/linux-compat/run.v'
 text := os.read_file(path)!
 assert !text.contains("name == 'semperm'")
 updated := text.replace('semabi,semword,sempid,semarray,semrange', 'semabi,semword,sempid,semarray,semrange,semperm')
  .replace("'semabi', 'semword', 'sempid', 'semarray', 'semrange'", "'semabi', 'semword', 'sempid', 'semarray', 'semrange', 'semperm'")
  .replace("\t\t\t} else if name == 'sysrq' {", "\t\t\t} else if name == 'semperm' {\n\t\t\t\t[marker, 'LINUX SEMPERM SUMMARY: checks=256552 failures=0']\n\t\t\t} else if name == 'sysrq' {")
 assert updated != text
 os.write_file(path, updated)!
 os.write_file(area + '/maintained-native.v', os.read_file(old + '/maintained-native.v')!
  .replace(old, area).replace("'/states/sr1-'", "'/states/sp1-'")
  .replace("root + '/tests/linux-compat/semrangefixture/core.v',", "root + '/tests/linux-compat/semrangefixture/core.v', root + '/tests/linux-compat/sempermfixture/core.v',")
  .replace("'semrange,semarray,sempid,semword,semabi'", "'semperm,semrange,semarray,sempid,semword,semabi'"))!
}
