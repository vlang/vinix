import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/priozombie-20261024'
const old = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const root = '/Users/alex/code/vinix'

fn main() {
 identity := json2.decode[map[string]json2.Any](os.read_file(area + '/prepared-source-inputs.json')!)!
 sources := identity['sources']!.as_map()
 mut checker := os.read_file(root + '/tests/linux-compat/priochange-evidence.v')!
 checker = checker.replace('priority change', 'zombie priority').replace('Priority change', 'Zombie priority')
 checker = checker.replace('priochange', 'priozombie').replace('PRIOCHANGE', 'PRIOZOMBIE')
 checker = checker.replace('23508', '1728').replace('23507', '1727').replace('5077', '1656').replace('5076', '1655')
 checker = checker.replace('if baseline { 16 }', 'if baseline { 20 }').replace('0 .. 16', '0 .. 20')
 checker = checker.replace('067b32e970372e6e55950480081340fa9d0b2a2a7f25f28dd189401b1495f426', sources['kernel/proc/nice.v']!.str())
 checker = checker.replace("const syscall_source = '18e4b5f08cf61819f66b2b803e74f842d9f61bf5d327b73d94f1b61f21770a01'", "const process_source = '" + sources['kernel/proc/proc.v']!.str() + "'\nconst exit_source = '" + sources['kernel/userland/exit.v']!.str() + "'")
 checker = checker.replace('ad2c4322bc23e230f46b3631ffc873a03057c09b', identity['base']!.str()).replace('4d5c21e0122b7eeee8e235f1154a9c701b5c7c9e', identity['commit']!.str())
 checker = checker.replace("digest(root + '/source/kernel/syscall/table/linux_common.v')! == syscall_source", "digest(root + '/source/kernel/proc/proc.v')! == process_source\n\t\t&& digest(root + '/source/kernel/userland/exit.v')! == exit_source")
 checker = checker.replace("input_pin(build.inputs_before, build_root + 'syscall/table/linux_common.v')! == syscall_source", "input_pin(build.inputs_before, build_root + 'proc/proc.v')! == process_source\n\t\t\t&& input_pin(build.inputs_before, build_root + 'userland/exit.v')! == exit_source")
 checker = checker.replace("['priozombie', 'prioquery', 'threadnice', 'niceabi', 'niceadmit', 'attrnice', 'groupabi', 'grouptid']", "['priozombie', 'priochange', 'prioquery', 'threadnice', 'groupabi', 'grouptid', 'groupzombie', 'waitabi']")
 checker = checker.replace("if name == 'prioquery' {\n", "if name == 'priochange' {\n\t\trequire(text.count('LINUX PRIOCHANGE SUMMARY: checks=23508 failures=0') == 1, 'Wrong priority change summary')!\n\t}\n\tif name == 'prioquery' {\n")
 checker = checker.replace("name in ['prioquery', 'threadnice']", "name in ['priochange', 'prioquery', 'threadnice']").replace("name == 'grouptid'", "name in ['grouptid', 'groupzombie', 'waitabi']")
 for pair in [['compile-fourth-', 'compile-third-'], ['kernel-third-', 'kernel-first-'], ['reference-second-', 'reference-third-'], ['candidate-first-', 'native-fixed-'], ['maintained-second-', 'maintained-first-'], ['baseline-second-', 'native-base-']] { checker = checker.replace(pair[0], pair[1]) }
 os.write_file(root + '/tests/linux-compat/priozombie-evidence.v', checker)!
 mut publisher := os.read_file(old + '/publish-second.v')!
 publisher = publisher.replace(old, area).replace('2026-10-23/priochange-evidence', '2026-10-24/priozombie-evidence')
 start := publisher.index(' for suffix in ["arm", "x86"] {') or { panic('missing publisher start') }
 end := publisher.index(' for name in ["generated-review.json"') or { panic('missing publisher end') }
 publisher = publisher[..start] + '
 for suffix in ["arm", "x86"] {
  directory(area + "/states/compile-third-" + suffix, suffix + "/compile", mut manifest)!
  for pair in [["native-base-", "baseline"], ["linux-third-", "reference"], ["native-fixed-", "native"], ["kernel-first-", "build"], ["n", "maintained"]] {
   ending := if pair[1] == "build" { "-prod" } else { "" }
   directory(area + "/states/" + pair[0] + suffix + ending, suffix + "/" + pair[1], mut manifest)!
  }
  for name in ["compile-first-", "compile-second-", "linux-second-"] {
   path := area + "/states/" + name + suffix
   if os.is_dir(path) { directory(path, "attempts/" + name + suffix, mut manifest)! }
  }
 }
 directory(area + "/frozen-third", "source/fixture", mut manifest)!
 for name in ["first", "second"] { directory(area + "/frozen-" + name, "attempts/frozen-" + name, mut manifest)! }
 directory(area + "/source/kernel", "source/kernel", mut manifest)!
 for name in ["priochange", "prioquery", "threadnice", "groupabi", "grouptid", "groupzombie", "waitabi"] {
  copy_file(root + "/tests/linux-compat/" + name + "fixture/core.v", "source/fixture/" + name + "fixture/core.v", mut manifest)!
 }
 copy_file(area + "/source.diff", "source/change.diff", mut manifest)!
 copy_file(area + "/prepared-source-inputs.json", "source/identity.json", mut manifest)!
' + publisher[end..]
 publisher = publisher.replace('priochange-reference.v', 'priozombie-reference.v').replace('priochange-evidence.v', 'priozombie-evidence.v')
 publisher = publisher.replace(' copy_file(area + "/linux-v6.12-sys.c"', ' copy_file(old_source_placeholder')
 publisher = publisher.replace('old_source_placeholder', '"' + old + '/linux-v6.12-sys.c"')
 // The initial preparer is outside the private task directory.
 publisher = publisher.replace(' copy_file(area + "/report.md"', ' copy_file("/Users/alex/.cache/vinix-linux-compat/prepare-priozombie.v", "tooling/private/prepare-priozombie.v", mut manifest)!\n copy_file(area + "/report.md"')
 os.write_file(area + '/publish.v', publisher)!
 mut finalizer := os.read_file(old + '/finalize-second.v')!
 finalizer = finalizer.replace(old, area).replace('2026-10-23/priochange-evidence', '2026-10-24/priozombie-evidence')
 finalizer = finalizer.replace('publish-second', 'publish-first').replace('evidence-controls-third', 'evidence-controls-first').replace('evidence-third', 'evidence-first')
 finalizer = finalizer.replace('priochange-reference.v', 'priozombie-reference.v').replace('priochange-evidence.v', 'priozombie-evidence.v')
 finalizer = finalizer.replace('["proc/nice.v", "syscall/table/linux_common.v"]', '["proc/nice.v", "proc/proc.v", "userland/exit.v"]')
 finalizer = finalizer.replace('["priochangefixture", "priochangereferenceinit", "prioqueryfixture", "threadnicefixture", "niceabifixture", "niceadmitfixture", "attrnicefixture", "groupabifixture", "grouptidfixture"]', '["priozombiefixture", "priozombiereferenceinit", "priochangefixture", "prioqueryfixture", "threadnicefixture", "groupabifixture", "grouptidfixture", "groupzombiefixture", "waitabifixture"]')
 os.write_file(area + '/finalize.v', finalizer)!
}
