import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'

fn main() {
 for module in ['prioqueryfixture', 'prioqueryreferenceinit'] {
  os.mkdir_all(root + '/tests/linux-compat/' + module)!
  source := if module == 'prioqueryfixture' { area + '/fixture/core.v' } else { area + '/' + module + '/core.v' }
  os.cp(source, root + '/tests/linux-compat/' + module + '/core.v')!
 }
 os.cp(area + '/reference.v', root + '/tests/linux-compat/prioquery-reference.v')!
 path := root + '/tests/linux-compat/run.v'
 mut text := os.read_file(path)!
 assert !text.contains('prioquery')
 text = text.replace('niceadmit,threadnice', 'niceadmit,threadnice,prioquery')
  .replace("'niceadmit', 'threadnice'", "'niceadmit', 'threadnice', 'prioquery'")
  .replace("} else if name == 'semabi' {", "} else if name == 'prioquery' {\n\t\t\t\t[marker, 'LINUX PRIOQUERY SUMMARY: checks=6199 failures=0']\n\t\t\t} else if name == 'semabi' {")
 os.write_file(path, text)!
 source := os.read_file('/Users/alex/.cache/vinix-linux-compat/semmeta-20261023/maintained-native.v')!
 start := source.index("        root + '/tests/linux-compat/run.v',") or { panic('Missing fixture list start') }
 end := source.index("        kernel + '/bin/vinix'") or { panic('Missing fixture list end') }
 controller := (source[..start] + "        root + '/tests/linux-compat/run.v',\n" + source[end..])
  .replace('/Users/alex/.cache/vinix-linux-compat/semmeta-20261023', area)
  .replace("state := previous + '/states/sm3-'", "state := area + '/states/maintained-first-'")
  .replace('semmeta,semperm,semrange,semarray,sempid,semword,semabi', 'prioquery,threadnice,niceabi,niceadmit,attrnice,groupabi,grouptid')
  .replace('    envhelper.configure()', "    for name in ['prioquery', 'threadnice', 'niceabi', 'niceadmit', 'attrnice', 'groupabi', 'grouptid'] {\n        path := root + '/tests/linux-compat/' + name + 'fixture/core.v'\n        inputs[path] = digest(path)\n    }\n    envhelper.configure()")
 os.write_file(area + '/maintained-native.v', controller)!
 println('Integrated native priority query fixture, reference, runner and private regression controller')
}
