import os

const area = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
const prior = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'
const root = '/Users/alex/code/vinix'

fn replace(text string, old string, new string) string {
 assert text.contains(old), 'Missing adaptation: ' + old
 return text.replace(old, new)
}

fn main() {
 mut checker := os.read_file(root + '/tests/linux-compat/semarray-evidence.v')!
 checker = replace(checker, '22b78bee6e8bbab1e3a84f45ab74574f81c6e5779b223ae6b02c4d3aebcd562c', '0ee9007d431ac0f225a59e391af2d379dcbb6380c6d6da813f0f2f1fa9adaab1')
 checker = replace(checker, '004aaa782d989515399ccdcd9e94b81094337dcb', 'f7db726bbba470e3b4746a90197a8b3958b62a78')
 checker = replace(checker, '25a48efae23ed887ecd45559d7ec8b929e224809', '7eb399c6e8da852729a04fa52943a848eb1b6c92')
 for pair in [['semarray-reference', 'semrange-reference'], ['semarrayreferenceinit', 'semrangereferenceinit'],
  ['semarray-evidence', 'semrange-evidence'], ['semaphore array', 'semaphore SETVAL range'], ['Semaphore array', 'Semaphore SETVAL range'], ['SEMARRAY', 'SEMRANGE']] {
  checker = replace(checker, pair[0], pair[1])
 }
 checker = replace(checker, "pid := kind == 'pid'", "pid := kind == 'pid'\n\tarray := kind == 'array'")
 checker = replace(checker, "else if pid { 'SEMPID' } else { 'SEMRANGE' }", "else if pid { 'SEMPID' } else if array { 'SEMARRAY' } else { 'SEMRANGE' }")
 checker = replace(checker, "} else if baseline {\n\t\t'457 failures=304'", "} else if array {\n\t\t'457 failures=0'\n\t} else if baseline {\n\t\t'4200 failures=240'")
 checker = replace(checker, "} else {\n\t\t'457 failures=0'", "} else {\n\t\t'4200 failures=0'")
 checker = replace(checker, 'if baseline { 304 }', 'if baseline { 240 }')
 checker = replace(checker, 'maintained.results.len == 4', 'maintained.results.len == 5')
 checker = replace(checker, '["semarray", "sempid", "semword", "semabi"]', '["semrange", "semarray", "sempid", "semword", "semabi"]')
 checker = replace(checker, 'else if result.name == "sempid" { "pid" } else { "native" }', 'else if result.name == "sempid" { "pid" } else if result.name == "semarray" { "array" } else { "native" }')
 checker = replace(checker, "['compile-third-', 'kernel-build1-', 'linux1-', 'native1-', 'maintained1-']", "['compile-second-', 'build-first-', 'reference-first-', 'native-first-', 'maintained-first-']")
 checker = replace(checker, "'/attempts/baseline1-'", "'/attempts/baseline-first-'")
 checker = replace(checker, '261/276/175-case semaphore regressions', '457/261/276/175-case semaphore regressions')
 checker = replace(checker, 'LINUX SEMRANGE SUMMARY: checks=457 failures=0', 'LINUX SEMRANGE SUMMARY: checks=4200 failures=0')
 checker = replace(checker, 'LINUX SEMRANGE SUMMARY: checks=457 failures=304', 'LINUX SEMRANGE SUMMARY: checks=4200 failures=240')
 checker = replace(checker, 'for _ in 0 .. 304', 'for _ in 0 .. 240')
 checker = replace(checker, "good.replace('457', '456')", "good.replace('4200', '4199')")
 checker = replace(checker, "baseline.replace('failures=304', 'failures=303')", "baseline.replace('failures=240', 'failures=239')")
 checker = replace(checker, "serial(good, 'native')!", "serial(good, 'native')!\n\tserial('LINUX SEMARRAY SUMMARY: checks=457 failures=0\\nLINUX SEMARRAY: PASS\\n', 'array')!")
 checker = replace(checker, 'reference-controls1', 'parser-controls')
 os.write_file(root + '/tests/linux-compat/semrange-evidence.v', checker)!

 mut publisher := os.read_file(prior + '/publish.v')!
 for pair in [['semarray-20261023', 'semrange-20261023'], ['semarray-evidence', 'semrange-evidence'], ['semarray-reference.v', 'semrange-reference.v'],
  ['compile-third-', 'compile-second-'], ['frozen-third', 'frozen-second'], ["'/states/sa1-'", "'/states/sr1-'"],
  ["['baseline-first-', 'baseline']", "['old-first-', 'baseline']"], ["['native-first-', 'native']", "['new-first-', 'native']"],
  ["['semabi', 'semword', 'sempid']", "['semabi', 'semword', 'sempid', 'semarray']"]] {
  publisher = replace(publisher, pair[0], pair[1])
 }
 publisher = replace(publisher, " directory(area + '/frozen-second', 'attempts/frozen-second', mut manifest)!\n directory(area + '/states/compile-second-arm', 'attempts/compile-second-arm', mut manifest)!\n", '')
 publisher = replace(publisher, "'build-kernels.v', 'prepare.v',", "'build-kernels.v',")
 publisher = replace(publisher, "'setup.v', 'reclaim-prior-media.v',", "'setup.v',")
 publisher = replace(publisher, " copy_file(area + '/report.md', 'README.md', mut manifest)!", " copy_file(area + '/report.md', 'README.md', mut manifest)!\n copy_file(area + '/linux-v6.12-sem.c', 'reference/linux-v6.12-sem.c', mut manifest)!")
 os.write_file(area + '/publish.v', publisher)!

 mut finalizer := os.read_file(prior + '/finalize.v')!
 for pair in [['semarray-20261023', 'semrange-20261023'], ['semarray-evidence', 'semrange-evidence'], ['semarray-reference.v', 'semrange-reference.v'],
  ["['semarrayfixture', 'semarrayreferenceinit', 'sempidfixture', 'semwordfixture', 'semabifixture']", "['semrangefixture', 'semrangereferenceinit', 'semarrayfixture', 'sempidfixture', 'semwordfixture', 'semabifixture']"]] {
  finalizer = replace(finalizer, pair[0], pair[1])
 }
 os.write_file(area + '/finalize.v', finalizer)!
 println('SETVAL evidence tooling prepared')
}
