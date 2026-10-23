import os

const area = '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'
const prior = '/Users/alex/.cache/vinix-linux-compat/semrange-20261023'
const root = '/Users/alex/code/vinix'

fn replace(text string, old string, new string) string {
 assert text.contains(old), 'Missing adaptation: ' + old
 return text.replace(old, new)
}

fn main() {
 mut checker := os.read_file(root + '/tests/linux-compat/semrange-evidence.v')!
 for pair in [
 ['0ee9007d431ac0f225a59e391af2d379dcbb6380c6d6da813f0f2f1fa9adaab1', '939e171c1d8f83e065208d99d7e60b25db032cbdbf8851ee055de72e835d43b6'],
 ['f7db726bbba470e3b4746a90197a8b3958b62a78', 'e5b423347e1aad8ef122316bb85602aab2d52e50'],
 ['7eb399c6e8da852729a04fa52943a848eb1b6c92', '99b997a347ea535c66128ba7858ccfeab1a32827'],
 ['semrange-reference', 'semperm-reference'], ['semrangereferenceinit', 'sempermreferenceinit'],
 ['semrange-evidence', 'semperm-evidence'], ['semaphore SETVAL range', 'semaphore permission'],
 ['Semaphore SETVAL range', 'Semaphore permission'], ['SEMRANGE', 'SEMPERM']] {
  checker = replace(checker, pair[0], pair[1])
 }
 checker = replace(checker, "array := kind == 'array'", "array := kind == 'array'\n\trange := kind == 'range'")
 checker = replace(checker, "else if array { 'SEMARRAY' } else { 'SEMPERM' }", "else if array { 'SEMARRAY' } else if range { 'SEMRANGE' } else { 'SEMPERM' }")
 checker = replace(checker, "} else if baseline {\n\t\t'4200 failures=240'", "} else if range {\n\t\t'4200 failures=0'\n\t} else if baseline {\n\t\t'256552 failures=95772'")
 checker = replace(checker, "} else {\n\t\t'4200 failures=0'", "} else {\n\t\t'256552 failures=0'")
 checker = replace(checker, 'if baseline { 240 }', 'if baseline { 100 }')
 checker = replace(checker, 'maintained.results.len == 5', 'maintained.results.len == 6')
 checker = replace(checker, '["semrange", "semarray", "sempid", "semword", "semabi"]', '["semperm", "semrange", "semarray", "sempid", "semword", "semabi"]')
 checker = replace(checker, 'else if result.name == "semarray" { "array" } else { "native" }', 'else if result.name == "semarray" { "array" } else if result.name == "semrange" { "range" } else { "native" }')
 checker = replace(checker, "['compile-second-', 'build-first-', 'reference-first-', 'native-first-', 'maintained-first-']", "['compile-fourth2-', 'build-first-', 'reference-second-', 'native-first-', 'maintained-first-']")
 checker = replace(checker, '457/261/276/175-case', '4200/457/261/276/175-case')
 checker = replace(checker, 'LINUX SEMPERM SUMMARY: checks=4200 failures=0', 'LINUX SEMPERM SUMMARY: checks=256552 failures=0')
 checker = replace(checker, 'LINUX SEMPERM SUMMARY: checks=4200 failures=240', 'LINUX SEMPERM SUMMARY: checks=256552 failures=95772')
 checker = replace(checker, 'for _ in 0 .. 240', 'for _ in 0 .. 100')
 checker = replace(checker, "good.replace('4200', '4199')", "good.replace('256552', '256551')")
 checker = replace(checker, "baseline.replace('failures=240', 'failures=239')", "baseline.replace('failures=95772', 'failures=95771')")
 checker = replace(checker, "serial(good, 'native')!", "serial(good, 'native')!\n\tserial('LINUX SEMRANGE SUMMARY: checks=4200 failures=0\\nLINUX SEMRANGE: PASS\\n', 'range')!")
 checker = replace(checker, 'parser-controls.status', 'parser-controls1.status')
 checker = replace(checker, 'parser-controls.log', 'parser-controls1.log')
 os.write_file(root + '/tests/linux-compat/semperm-evidence.v', checker)!

 mut publisher := os.read_file(prior + '/publish.v')!
 for pair in [['semrange-20261023', 'semperm-20261023'], ['semrange-evidence', 'semperm-evidence'], ['semrange-reference.v', 'semperm-reference.v'],
  ['compile-second-', 'compile-fourth-'], ['linux-first-', 'linux-second-'], ['frozen-second', 'frozen-fourth'], ["'/states/sr1-'", "'/states/sp1-'"],
  ["['semabi', 'semword', 'sempid', 'semarray']", "['semabi', 'semword', 'sempid', 'semarray', 'semrange']"]] {
  publisher = replace(publisher, pair[0], pair[1])
 }
 publisher = replace(publisher, "  directory(area + '/states/compile-first-' + suffix, 'attempts/compile-first-' + suffix, mut manifest)!", "  for attempt in ['first', 'second', 'third'] {\n   path := area + '/states/compile-' + attempt + '-' + suffix\n   if os.is_dir(path) { directory(path, 'attempts/compile-' + attempt + '-' + suffix, mut manifest)! }\n  }")
 publisher = replace(publisher, " directory(area + '/frozen-first', 'attempts/frozen-first', mut manifest)!", " for attempt in ['first', 'second', 'third'] { directory(area + '/frozen-' + attempt, 'attempts/frozen-' + attempt, mut manifest)! }\n directory(area + '/states/linux-first-arm', 'attempts/reference-first-arm', mut manifest)!")
 publisher = replace(publisher, "'publish.v', 'setup.v', 'removed-prior-media-pins.json'", "'publish.v', 'setup.v', 'fix-fixture.v', 'document-report.v'")
 publisher = replace(publisher, " copy_file(area + '/linux-v6.12-sem.c', 'reference/linux-v6.12-sem.c', mut manifest)!", " copy_file(area + '/linux-v6.12-sem.c', 'reference/linux-v6.12-sem.c', mut manifest)!\n copy_file(area + '/linux-v6.12-util.c', 'reference/linux-v6.12-util.c', mut manifest)!")
 os.write_file(area + '/publish.v', publisher)!

 mut finalizer := os.read_file(prior + '/finalize.v')!
 for pair in [['semrange-20261023', 'semperm-20261023'], ['semrange-evidence', 'semperm-evidence'], ['semrange-reference.v', 'semperm-reference.v'],
  ["['semrangefixture', 'semrangereferenceinit',", "['sempermfixture', 'sempermreferenceinit', 'semrangefixture',"]] {
  finalizer = replace(finalizer, pair[0], pair[1])
 }
 os.write_file(area + '/finalize.v', finalizer)!
 println('Semaphore permission evidence tooling prepared')
}
