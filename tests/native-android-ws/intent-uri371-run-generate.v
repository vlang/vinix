// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the qualified369 oracle while retaining its actual old367 control.
module main
import os

fn replace_once(source string, before string, after string) string {
 assert source.count(before) == 1, before
 return source.replace(before, after)
}

fn main() {
 base := os.read_file('tests/native-android-ws/intent-uri369-run.v')!
 mut s := base.replace('369', '371')
 s = replace_once(s, '// Same-APK ART regression; preparation builds only a runner and one fixture APK.',
  '// Same-APK ART successor: retain the actual369 old367 control and boot only new371.')
 s = replace_once(s, "const baseline_pin =", "const origin = '/Users/alex/.local/state/vinix/android/intent-uri369-fixture-2026-10-26'\nconst snapshot = '/Users/alex/.local/state/vinix/android/intent-uri369-failure-readback-b-2026-10-26'\nconst original_inventory = '6e2288faa9a4eb14f3a5495a751b1298d1e179e181eba247627880748181da4b'\nconst original_receipt = '0f91fd7499563acb0cb863b04e078d2390210986d53e8888f9c1f7558a706e96'\nconst original_apk = '710eeaa6cc2b5f0d5ddd0fde5b3b62e71e844220c20584846f121dbbe13eec85'\nconst original_runner = '3229369e8b908233b6d6dcd0a8b7aa2d45697c734de3e11ebe38c84082e10d33'\nconst original_new_jar = '74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b'\nconst baseline_pin =")
 s = replace_once(s, "'generated-c', 'apk', 'initial-media']", "'generated-c', 'apk', 'initial-media', 'control369']")
 s = replace_once(s, "'initial-media.json', 'build-pins.json']", "'initial-media.json', 'build-pins.json', 'control-origin.json', 'control-sha256.json',\n  'control-origin-inventory.json', 'control-failure-receipt.json']")
 s = replace_once(s, "clone(baseline + '/apk/fixture.p12', state + '/apk/fixture.p12')!", "clone(origin + '/apk', state + '/apk')!\n assert hash(state + '/apk/probe.apk')! == original_apk")
 s = replace_once(s, " compile('fixture-driver', driver + '|' + vroot + '/vlib', driver, state + '/tools/fixture-driver')!\n record('fixture-smali', [state + '/tools/fixture-driver', state + '/apk'])!", " // Reuse the already signed byte-identical APK; retain its original build provenance below.")
 s = replace_once(s, ' build_apk()!', ' retain_control()!')
 s = replace_once(s, " write_json(state + '/shared-inputs.json', stable()!)!", " write_json(state + '/shared-inputs.json', stable()!)!\n check_control(state + '/old-semantic-check.json')!")
 s = replace_once(s, " assert kind in ['old', 'new'] && !os.exists(state + '/sha256.json')", " assert kind == 'new' && !os.exists(state + '/sha256.json'), 'the old367 guest is retained, never rerun'")
 s = replace_once(s, "fn check(kind string, receipt string) ! {\n", "fn check(kind string, receipt string) ! {\n if kind == 'old' { check_control(receipt)!; return }\n")
 s = replace_once(s, "  'old', 'new' { run(os.args[1])! }", "  'new' { run('new')! }")
 s = replace_once(s, ' | old | new | qualify | seal | self-test', ' | new | qualify | seal | self-test')
 s += '\n' + os.read_file('tests/native-android-ws/intent-uri371-control.v')!.all_after('module main\n')
 os.write_file('tests/native-android-ws/intent-uri371-run.v', s)!
 assert s.all_after('fn semantic_at(').all_before('\nfn check(') == base.all_after('fn semantic_at(').all_before('\nfn check(')
 println('INTENT371-GENERATED unchanged semantic_at and fixture; retained actual old367 control')
}
