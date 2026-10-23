import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/semmeta-20261023'
const prior = '/Users/alex/.cache/vinix-linux-compat/semperm-20261023'

fn main() {
 mut checker := os.read_file(root + '/tests/linux-compat/semperm-evidence.v')!
 checker = checker.replace('939e171c1d8f83e065208d99d7e60b25db032cbdbf8851ee055de72e835d43b6', '29bed8c38a9de3b927c06b21ef25a956db52c5205b0410c3b5aa012026d2b3c1')
  .replace('e5b423347e1aad8ef122316bb85602aab2d52e50', 'd2283facaf4c5db67d48cae8194e3000f2689575')
  .replace('99b997a347ea535c66128ba7858ccfeab1a32827', '09bf0cfff672c584c351642260bfe6a8a9513892')
  .replace('semperm', 'semmeta').replace('SEMPERM', 'SEMMETA')
  .replace('256552', '28713').replace('95772', '19480').replace('95771', '19479')
  .replace('256551', '28712').replace('permission', 'metadata')
  .replace('mismatches == if baseline { 100 }', 'mismatches == if baseline { 96 }')
  .replace('0 .. 100', '0 .. 96')
  .replace('maintained.results.len == 6', 'maintained.results.len == 7')
  .replace('["semmeta", "semrange"', '["semmeta", "semperm", "semrange"')
  .replace('else { "native" })!', 'else if result.name == "semperm" { "permission" } else { "native" })!')
  .replace("\trange := kind == 'range'", "\tpermission := kind == 'permission'\n\trange := kind == 'range'")
  .replace("else { 'SEMMETA' }", "else if permission { 'SEMPERM' } else { 'SEMMETA' }")
  .replace("} else if baseline {\n\t\t'28713", "} else if permission {\n\t\t'256552 failures=0'\n\t} else if baseline {\n\t\t'28713")
  .replace("['compile-fourth2-', 'build-first-', 'reference-second-', 'native-first-', 'maintained-first-']", "['compile-fifth-', 'build-first-', 'reference-third-', 'native-second-', 'maintained-second-']")
  .replace("prefix + suffix + '.status'", "prefix + suffix + if prefix == 'compile-fifth-' { '-record.status' } else { '.status' }")
  .replace('baseline-first-', 'baseline-second-')
  .replace('parser-controls1', 'reference-controls-first')
  .replace('4200/457/261/276/175-case', '256552/4200/457/261/276/175-case')
 os.write_file(root + '/tests/linux-compat/semmeta-evidence.v', checker)!
 mut publisher := os.read_file(prior + '/publish.v')!.replace(prior, area)
  .replace('semperm-evidence', 'semmeta-evidence')
  .replace('compile-fourth-', 'compile-fifth-').replace('frozen-fourth', 'frozen-fifth')
  .replace("['old-first-', 'baseline'], ['linux-second-', 'reference'], ['new-first-', 'native']", "['old-second-', 'baseline'], ['linux-third-', 'reference'], ['new-second-', 'native']")
  .replace("'/states/sp1-'", "'/states/sm2-'")
  .replace("['first', 'second', 'third']", "['first', 'second', 'third', 'fourth']")
  .replace("['semabi', 'semword', 'sempid', 'semarray', 'semrange']", "['semabi', 'semword', 'sempid', 'semarray', 'semrange', 'semperm']")
  .replace("['semperm-reference.v', 'semperm-evidence.v', 'run.v']", "['semmeta-reference.v', 'semmeta-evidence.v', 'run.v']")
  .replace("'setup.v', 'fix-fixture.v', 'document-report.v'", "'setup.v', 'document-report.v'")
 publisher = publisher.replace(" directory(area + '/states/linux-first-arm', 'attempts/reference-first-arm', mut manifest)!", " for suffix in ['arm', 'x86'] {\n  for pair in [['linux-first-', 'reference-first-'], ['linux-second-', 'reference-second-'], ['old-first-', 'baseline-first-'], ['new-first-', 'native-first-']] {\n   source := area + '/states/' + pair[0] + suffix\n   if os.is_dir(source) { directory(source, 'attempts/' + pair[1] + suffix, mut manifest)! }\n  }\n  directory(previous + '/states/sm1-' + suffix, 'attempts/maintained-first-' + suffix, mut manifest)!\n }")
 os.write_file(area + '/publish.v', publisher)!
 mut maintained := os.read_file(area + '/maintained-native.v')!
 maintained = maintained.replace("'/states/sm1-'", "'/states/sm2-'")
 os.write_file(area + '/maintained-native.v', maintained)!
 finalizer := os.read_file(prior + '/finalize.v')!.replace(prior, area).replace('semperm-evidence', 'semmeta-evidence')
  .replace('semperm-reference.v', 'semmeta-reference.v').replace("['sempermfixture', 'sempermreferenceinit',", "['semmetafixture', 'semmetareferenceinit', 'sempermfixture',")
 os.write_file(area + '/finalize.v', finalizer)!
 println('Metadata evidence tools prepared')
}
