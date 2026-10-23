import os
const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'
const root = '/Users/alex/code/vinix'
fn main() {
 for name in ['priochangefixture', 'serialcore', 'priochangereferenceinit'] {
  os.mkdir_all(area + '/frozen-third/' + name)!
  from := if name == 'priochangefixture' { root + '/tests/linux-compat/' + name } else { area + '/frozen-first/' + name }
  os.cp(from + '/core.v', area + '/frozen-third/' + name + '/core.v')!
 }
 runner := os.read_file(root + '/tests/linux-compat/run.v')!
 assert runner.count('threadnice,prioquery,randomflags') == 2
 revised := runner.replace('threadnice,prioquery,randomflags', 'threadnice,prioquery,priochange,randomflags')
  .replace("'threadnice', 'prioquery', 'randomflags'", "'threadnice', 'prioquery', 'priochange', 'randomflags'")
  .replace("} else if name == 'prioquery' {", "} else if name == 'priochange' {\n\t\t\t\t[marker, 'LINUX PRIOCHANGE SUMMARY: checks=23508 failures=0']\n\t\t\t} else if name == 'prioquery' {")
 os.write_file(root + '/tests/linux-compat/run.v', revised)!
 maintained := os.read_file(old + '/maintained-fourth.v')!.replace(old, area)
  .replace("'/states/m4'", "'/states/m'").replace('/states/kernel-second-', '/states/kernel-first-')
  .replace("'prioquery', 'threadnice'", "'priochange', 'prioquery', 'threadnice'")
  .replace('prioquery,threadnice', 'priochange,prioquery,threadnice')
 os.write_file(area + '/maintained.v', maintained)!
 os.write_file(area + '/arm-cc-third.v', os.read_file(old + '/arm-cc-third.v')!.replace(old, area))!
}
