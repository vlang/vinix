import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/prioquery-20261023'

fn main() {
 mut checker := os.read_file(root + '/tests/linux-compat/prioquery-evidence.v')!
 for a, b in {
  'prioquery': 'priochange', 'PRIOQUERY': 'PRIOCHANGE', 'priority query': 'priority change',
  'Priority query': 'Priority change', '6199': '23508', '6198': '23507',
  '403': '5077', '402': '5076', 'seven maintained': 'eight maintained',
  "maintained.results.len == 7": "maintained.results.len == 8",
  "['priochange', 'threadnice'": "['priochange', 'prioquery', 'threadnice'",
  '950db21493f4edab4bf9be97407f4f546397ce82e65a6a263e076f5d9aaff8ae': '067b32e970372e6e55950480081340fa9d0b2a2a7f25f28dd189401b1495f426',
  'f125c27895e9e28ea346207211907868a1d2f24cb61faa489c50d2189ffb33c7': '18e4b5f08cf61819f66b2b803e74f842d9f61bf5d327b73d94f1b61f21770a01',
  'a544610c9f559e97e86c38dc931c0c8125e174c9': 'ad2c4322bc23e230f46b3631ffc873a03057c09b',
  '730d43fb3d1505c4e7f8ad92c5292586d9c841db': '4d5c21e0122b7eeee8e235f1154a9c701b5c7c9e',
 } { checker = checker.replace(a, b) }
 checker = checker.replace("if name == 'priochange' { serial(text, 'native')!; return }", "if name == 'priochange' { serial(text, 'native')!; return }\n\tif name == 'prioquery' {\n\t\trequire(text.count('LINUX PRIOQUERY SUMMARY: checks=6199 failures=0') == 1, 'Wrong priority query summary')!\n\t}")
 checker = checker.replace("expected := if name == 'threadnice'", "expected := if name in ['prioquery', 'threadnice']")
 checker = checker.replace("maintained_attempt := if suffix == 'arm' { 'third' } else { 'fourth' }\n\t\t", '')
 checker = checker.replace("'compile-second-' + suffix + '-record', 'kernel-second-' + suffix + '-record',\n\t\t\t'reference-first-' + suffix, 'candidate-second-' + suffix, 'maintained-' + maintained_attempt + '-' + suffix + '-record'", "'compile-fourth-' + suffix + '-record', 'kernel-third-' + suffix + '-record',\n\t\t\t'reference-second-' + suffix + '-record', 'candidate-first-' + suffix + '-record', 'maintained-first-' + suffix + '-record'")
 checker = checker.replace("'baseline-first-' + suffix + '.status'", "'baseline-second-' + suffix + '-record.status'")
 os.write_file(root + '/tests/linux-compat/priochange-evidence.v', checker)!
 maintained := os.read_file(area + '/maintained.v')!
 os.write_file(area + '/maintained-third.v', maintained.replace('kernel-second-', 'kernel-third-'))!
 println('Prepared priority change checker and maintained build path')
}
