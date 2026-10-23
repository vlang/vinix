import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
 root := '/Users/alex/code/vinix'
 controller := os.read_file(area + '/maintained-third.v')!.replace("'/states/m'", "'/states/n'")
 os.write_file(area + '/maintained-fourth.v', controller)!
 publisher := os.read_file(area + '/publish-first.v')!.replace('directory(area + "/states/m" + suffix, suffix + "/maintained", mut manifest)!', 'directory(area + "/states/n" + suffix, suffix + "/maintained", mut manifest)!\n  directory(area + "/states/m" + suffix, "attempts/maintained-first-" + suffix, mut manifest)!')
 os.write_file(area + '/publish-second.v', publisher)!
 checker_path := root + '/tests/linux-compat/priochange-evidence.v'
 checker := os.read_file(checker_path)!.replace("'maintained-first-' + suffix + '-record'", "'maintained-second-' + suffix + '-record'")
 os.write_file(checker_path, checker)!
 finalizer := os.read_file(area + '/finalize-first.v')!.replace('publish-first', 'publish-second').replace('evidence-controls-second', 'evidence-controls-third').replace('evidence-second', 'evidence-third')
 os.write_file(area + '/finalize-second.v', finalizer)!
 for path in [area + '/report.md', root + '/docs/linux-posix-qualification.md'] {
  old := os.read_file(path)!
  needle := 'fixture versions and the first kernel candidate remain retained.'
  replacement := needle + '\nThe first maintained run stopped during niceadmit compilation when the host\ndisk filled; the first four suites had passed on each architecture. Fresh\nsecond runs completed all eight suites after space was recovered. Partial\nfirst-run artifacts and the available disk-exhaustion log remain retained.'
  assert old.contains(needle)
  os.write_file(path, old.replace(needle, replacement))!
 }
}
