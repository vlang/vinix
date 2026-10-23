import os

fn main() {
 root := '/Users/alex/code/vinix'
 path := root + '/tests/linux-compat/run.v'
 mut text := os.read_file(path)!
 assert !text.contains("name == 'semmeta'")
 text = text.replace('semrange,semperm', 'semrange,semperm,semmeta')
 text = text.replace("'semrange', 'semperm']", "'semrange', 'semperm', 'semmeta']")
 text = text.replace("} else if name == 'semperm' {", "} else if name == 'semmeta' {\n\t\t\t\t[marker, 'LINUX SEMMETA SUMMARY: checks=28713 failures=0']\n\t\t\t} else if name == 'semperm' {")
 os.write_file(path, text)!
 area := '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'
 controller := os.read_file(area + '/maintained-native.v')!.replace("'/states/sp1-'", "'/states/sm1-'")
  .replace("root + '/tests/linux-compat/semmetafixture/core.v',", "root + '/tests/linux-compat/semmetafixture/core.v', root + '/tests/linux-compat/sempermfixture/core.v',")
  .replace('semmeta,semrange,semarray,sempid,semword,semabi', 'semmeta,semperm,semrange,semarray,sempid,semword,semabi')
 os.write_file(area + '/maintained-native.v', controller)!
}
