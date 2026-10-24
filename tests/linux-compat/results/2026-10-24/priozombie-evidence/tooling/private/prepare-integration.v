import os
const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const old = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
fn main() {
 runner := os.read_file(root + '/tests/linux-compat/run.v')!
 assert runner.count('prioquery,priochange,randomflags') == 2
 os.write_file(root + '/tests/linux-compat/run.v', runner.replace('prioquery,priochange,randomflags', 'prioquery,priochange,priozombie,randomflags')
  .replace("'prioquery', 'priochange', 'randomflags'", "'prioquery', 'priochange', 'priozombie', 'randomflags'")
  .replace("} else if name == 'priochange' {", "} else if name == 'priozombie' {\n\t\t\t\t[marker, 'LINUX PRIOZOMBIE SUMMARY: checks=1728 failures=0']\n\t\t\t} else if name == 'priochange' {"))!
 old_cases := "'priochange', 'prioquery', 'threadnice', 'niceabi', 'niceadmit', 'attrnice', 'groupabi', 'grouptid'"
 new_cases := "'priozombie', 'priochange', 'prioquery', 'threadnice', 'groupabi', 'grouptid', 'groupzombie', 'waitabi'"
 maintained := os.read_file(old + '/maintained-fourth.v')!.replace(old, area)
  .replace('/states/kernel-third-', '/states/kernel-first-')
  .replace(old_cases, new_cases)
  .replace('priochange,prioquery,threadnice,niceabi,niceadmit,attrnice,groupabi,grouptid', 'priozombie,priochange,prioquery,threadnice,groupabi,grouptid,groupzombie,waitabi')
 os.write_file(area + '/maintained.v', maintained)!
 os.write_file(area + '/arm-cc-third.v', os.read_file(old + '/arm-cc-third.v')!.replace(old, area))!
}
