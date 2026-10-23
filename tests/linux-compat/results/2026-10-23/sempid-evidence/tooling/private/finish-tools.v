import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/sempid-20261023'

fn replace(text string, old string, new string) string {
    assert text.contains(old), 'Missing template: ' + old
    return text.replace(old, new)
}

fn main() {
    mut checker := os.read_file(root + '/tests/linux-compat/semword-evidence.v')!
    checker = checker.replace('0e4a76e878aeb15a498e856dd8b8c7e32fa36fd35ff401a941f2152278270c9f', 'c9c74221120bc1dd4c8695eb59a4f151604a4449bef6439e796b89824ecdc186')
    checker = checker.replace('51451adf1564de86e531b1de5a70f558d9bdb9b3', '955b4af34bd668722631cef7926be5a0a22cec1e')
    checker = replace(checker, "const integration_candidate = '955b4af34bd668722631cef7926be5a0a22cec1e'", "const integration_candidate = '004aaa782d989515399ccdcd9e94b81094337dcb'")
    checker = checker.replace('semword-reference', 'sempid-reference').replace('semwordreferenceinit', 'sempidreferenceinit')
    checker = replace(checker, "regression := kind == 'regression'", "regression := kind == 'regression'\n\tword := kind == 'word'")
    checker = replace(checker, "name := if regression { 'SEMABI' } else { 'SEMWORD' }", "name := if regression { 'SEMABI' } else if word { 'SEMWORD' } else { 'SEMPID' }")
    checker = replace(checker, "'175 failures=0'\n\t} else if baseline", "'175 failures=0'\n\t} else if word {\n\t\t'276 failures=0'\n\t} else if baseline")
    checker = checker.replace('276 failures=89', '261 failures=79')
    checker = replace(checker, "} else {\n\t\t'276 failures=0'", "} else {\n\t\t'261 failures=0'")
    checker = replace(checker, 'if baseline { 89 } else { 0 }', 'if baseline { 79 } else { 0 }')
    checker = replace(checker, 'maintained.results.len == 2', 'maintained.results.len == 3')
    checker = replace(checker, '["semword", "semabi"]', '["sempid", "semword", "semabi"]')
    checker = replace(checker, 'if result.name == "semabi" { "regression" } else { "native" }', 'if result.name == "semabi" { "regression" } else if result.name == "semword" { "word" } else { "native" }')
    checker = replace(checker, "good := 'LINUX SEMWORD SUMMARY: checks=276 failures=0\\nLINUX SEMWORD: PASS\\n'", "good := 'LINUX SEMPID SUMMARY: checks=261 failures=0\\nLINUX SEMPID: PASS\\n'")
    checker = replace(checker, "good.replace('276', '275')", "good.replace('261', '260')")
    checker = checker.replace("good.replace('LINUX SEMWORD: PASS", "good.replace('LINUX SEMPID: PASS").replace("good + 'LINUX SEMWORD MISMATCH", "good + 'LINUX SEMPID MISMATCH")
    checker = replace(checker, "serial(good, 'native')!", "serial(good, 'native')!\n\tserial('LINUX SEMWORD SUMMARY: checks=276 failures=0\\nLINUX SEMWORD: PASS\\n', 'word')!")
    checker = checker.replace('semword-evidence --self-test', 'sempid-evidence --self-test').replace('Native semaphore ABI evidence:', 'Native semaphore PID evidence:').replace('Semaphore ABI evidence controls:', 'Semaphore PID evidence controls:').replace('and 175-case ABI regression', 'and 276/175-case ABI regressions')
    os.write_file(root + '/tests/linux-compat/sempid-evidence.v', checker)!

    mut publisher := os.read_file('/Users/alex/.cache/vinix-linux-compat/semword-20261023/publish.v')!
    publisher = publisher.replace('semword-20261023', 'sempid-20261023').replace('/semword-evidence', '/sempid-evidence')
    start := publisher.index("  directory(area + '/states/compile-probe4-") or { panic('Missing collector start') }
    end := publisher.index(" copy_file(area + '/sysvsem-candidate.v'") or { panic('Missing collector end') }
    publisher = publisher[..start] + "  directory(area + '/states/compile-second-' + suffix, suffix + '/compile', mut manifest)!\n  for pair in [['baseline-first-', 'baseline'], ['linux-first-', 'reference'], ['native-first-', 'native']] {\n   directory(area + '/states/' + pair[0] + suffix, suffix + '/' + pair[1], mut manifest)!\n  }\n  directory(area + '/states/kernel-first-' + suffix + '-prod', suffix + '/build', mut manifest)!\n  directory(previous + '/states/spid1-' + suffix, suffix + '/maintained', mut manifest)!\n  directory(area + '/states/compile-first-' + suffix, 'attempts/compile-first-' + suffix, mut manifest)!\n }\n directory(area + '/frozen-second', 'source/fixture', mut manifest)!\n directory(area + '/frozen-first', 'attempts/frozen-first', mut manifest)!\n for name in ['semabi', 'semword'] {\n  copy_file(root + '/tests/linux-compat/' + name + 'fixture/core.v', 'source/fixture/' + name + 'fixture/core.v', mut manifest)!\n }\n" + publisher[end..]
    publisher = publisher.replace("['semword-reference.v', 'semword-evidence.v', 'run.v']", "['sempid-reference.v', 'sempid-evidence.v', 'run.v']")
    publisher = replace(publisher, "'prepare-build.v', 'continue-tools.v',", "'prepare.v', 'integrate-runner.v', 'finish-tools.v',")
    publisher = replace(publisher, "if os.dir(path) == area &&", "if os.dir(path) == area + '/states' &&")
    os.write_file(area + '/publish.v', publisher)!
    println('Prepared PID evidence checker and collector')
}
