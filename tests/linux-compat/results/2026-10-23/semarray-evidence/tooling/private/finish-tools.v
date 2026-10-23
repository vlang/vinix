import os

const area = '/Users/alex/.cache/vinix-linux-compat/semarray-20261023'
const prior = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'
const root = '/Users/alex/code/vinix'

fn replace(text string, old string, new string) string {
 assert text.contains(old), 'Missing adaptation: ' + old
 return text.replace(old, new)
}

fn main() {
 mut checker := os.read_file(root + '/tests/linux-compat/sempid-evidence.v')!
 checker = replace(checker, 'c9c74221120bc1dd4c8695eb59a4f151604a4449bef6439e796b89824ecdc186', '22b78bee6e8bbab1e3a84f45ab74574f81c6e5779b223ae6b02c4d3aebcd562c')
 checker = replace(checker, "'004aaa782d989515399ccdcd9e94b81094337dcb'", "'25a48efae23ed887ecd45559d7ec8b929e224809'")
 checker = replace(checker, '955b4af34bd668722631cef7926be5a0a22cec1e', '004aaa782d989515399ccdcd9e94b81094337dcb')
 checker = replace(checker, 'sempid-reference.v', 'semarray-reference.v')
 checker = replace(checker, 'sempidreferenceinit', 'semarrayreferenceinit')
 checker = replace(checker, 'sempid-evidence', 'semarray-evidence')
 checker = replace(checker, 'semaphore PID', 'semaphore array')
 checker = replace(checker, 'Semaphore PID', 'Semaphore array')
 checker = replace(checker, 'SEMPID', 'SEMARRAY')
 checker = replace(checker, "word := kind == 'word'", "word := kind == 'word'\n\tpid := kind == 'pid'")
 checker = replace(checker, "else if word { 'SEMWORD' } else { 'SEMARRAY' }", "else if word { 'SEMWORD' } else if pid { 'SEMPID' } else { 'SEMARRAY' }")
 checker = replace(checker, "} else if baseline {\n\t\t'261 failures=79'", "} else if pid {\n\t\t'261 failures=0'\n\t} else if baseline {\n\t\t'457 failures=304'")
 checker = replace(checker, "} else {\n\t\t'261 failures=0'", "} else {\n\t\t'457 failures=0'")
 checker = replace(checker, 'if baseline { 79 }', 'if baseline { 304 }')
 checker = replace(checker, 'maintained.results.len == 3', 'maintained.results.len == 4')
 checker = replace(checker, '["sempid", "semword", "semabi"]', '["semarray", "sempid", "semword", "semabi"]')
 checker = replace(checker, 'else if result.name == "semword" { "word" } else { "native" }', 'else if result.name == "semword" { "word" } else if result.name == "sempid" { "pid" } else { "native" }')
 checker = replace(checker, "['compile2-', 'build1-'", "['compile-third-', 'kernel-build1-'")
 checker = replace(checker, '276/175-case ABI regressions', '261/276/175-case semaphore regressions')
 checker = replace(checker, 'LINUX SEMARRAY SUMMARY: checks=261 failures=0', 'LINUX SEMARRAY SUMMARY: checks=457 failures=0')
 checker = replace(checker, 'LINUX SEMARRAY SUMMARY: checks=261 failures=79', 'LINUX SEMARRAY SUMMARY: checks=457 failures=304')
 checker = replace(checker, 'for _ in 0 .. 79', 'for _ in 0 .. 304')
 checker = replace(checker, "good.replace('261', '260')", "good.replace('457', '456')")
 checker = replace(checker, "baseline.replace('failures=79', 'failures=78')", "baseline.replace('failures=304', 'failures=303')")
 checker = replace(checker, "serial(good, 'native')!", "serial(good, 'native')!\n\tserial('LINUX SEMPID SUMMARY: checks=261 failures=0\\nLINUX SEMPID: PASS\\n', 'pid')!")
 os.write_file(root + '/tests/linux-compat/semarray-evidence.v', checker)!

 mut publisher := os.read_file(prior + '/publish.v')!
 publisher = replace(publisher, 'sempid-20261023', 'semarray-20261023')
 publisher = replace(publisher, 'sempid-evidence', 'semarray-evidence')
 publisher = replace(publisher, 'sempid-reference.v', 'semarray-reference.v')
 publisher = replace(publisher, 'compile-second-', 'compile-third-')
 publisher = replace(publisher, 'frozen-second', 'frozen-third')
 publisher = replace(publisher, "'/states/spid1-'", "'/states/sa1-'")
 publisher = replace(publisher, "['semabi', 'semword']", "['semabi', 'semword', 'sempid']")
 publisher = replace(publisher, "directory(area + '/frozen-first', 'attempts/frozen-first', mut manifest)!", "directory(area + '/frozen-first', 'attempts/frozen-first', mut manifest)!\n directory(area + '/frozen-second', 'attempts/frozen-second', mut manifest)!\n directory(area + '/states/compile-second-arm', 'attempts/compile-second-arm', mut manifest)!")
 publisher = replace(publisher, "'publish.v', 'recover-export.v', 'partial-export-pins.json'", "'publish.v', 'setup.v', 'reclaim-prior-media.v', 'removed-prior-media-pins.json'")
 os.write_file(area + '/publish.v', publisher)!

 mut finalizer := os.read_file(prior + '/finalize.v')!
 finalizer = replace(finalizer, 'sempid-20261023', 'semarray-20261023')
 finalizer = replace(finalizer, 'sempid-evidence', 'semarray-evidence')
 finalizer = replace(finalizer, 'sempid-reference.v', 'semarray-reference.v')
 finalizer = replace(finalizer, 'publish2', 'publish1')
 finalizer = replace(finalizer, "['sempidfixture', 'sempidreferenceinit', 'semwordfixture', 'semabifixture']", "['semarrayfixture', 'semarrayreferenceinit', 'sempidfixture', 'semwordfixture', 'semabifixture']")
 os.write_file(area + '/finalize.v', finalizer)!
 println('Array evidence tooling prepared')
}
