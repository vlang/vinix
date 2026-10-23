import os

const area = '/Users/alex/.cache/vinix-linux-compat/semword-20261023'
const old = '/Users/alex/.cache/vinix-linux-compat/semabi-20261023'
const root = '/Users/alex/code/vinix'

fn main() {
 mut wrapper := os.read_file(old + '/maintained-native.v')!
 wrapper = wrapper.replace('semabi-20261023', 'semword-20261023')
 wrapper = wrapper.replace("if suffix == 'arm' { previous + '/states/semabi-maintained-integration2-arm' } else { area + '/states/maintained-integration2-x86' }", "previous + '/states/sw1-' + suffix")
 wrapper = wrapper.replace('kernel-integration4-', 'kernel-native1-')
 wrapper = wrapper.replace("area + '/maintained-run'", "area + '/maintained'")
 wrapper = wrapper.replace("root + '/tests/linux-compat/semabifixture/core.v',", "root + '/tests/linux-compat/semabifixture/core.v', root + '/tests/linux-compat/semwordfixture/core.v',")
 wrapper = wrapper.replace("'--cases', 'semabi'", "'--cases', 'semword,semabi'")
 os.write_file(area + '/maintained-native.v', wrapper)!
 mut review := os.read_file(old + '/review-generated.v')!
 review = review.replace('semabi-20261023', 'semword-20261023')
 review = review.replace('sysvsem__operate(i64 id', 'sysvsem__operate(i32 id')
 review = review.replace('void* _0, i64 id, i64 number, i64 command', 'void* _0, i32 id, i32 number, i32 command')
 review = review.replace("assert control.contains('i32 value = (i32)(argument);')", "assert control.contains('i32 value = (i32)(argument);')\n        get := body(text, 'multi_return_u64_u64 sysvsem__syscall_semget(void* _0, i32 key, i32 nsems, i32 flags)')!\n        validation := get.index('nsems < 0') or { panic('Missing signed count validation') }\n        lookup := get.index('sysvsem__find_key_unlocked') or { panic('Missing key lookup') }\n        assert validation < lookup\n        assert get.contains('nsems >')\n        assert get.contains('(i64)(nsems)')")
 review = review.replace("control + '\\n' + operate", "get + '\\n' + control + '\\n' + operate")
 review = review.replace('PASS: signed i32 SETVAL, unsigned u32 count, stack timeout and operation vector, timeout import before count/vector and duration validation before ID lookup', 'PASS: signed i32 semaphore IDs, semget count/flags and semctl number/command; signed count validation before key lookup; preserved u32 operation count, i32 SETVAL and stack import ordering')
 os.write_file(area + '/review-generated.v', review)!
 mut checker := os.read_file(root + '/tests/linux-compat/semabi-evidence.v')!
 checker = checker.replace('a2236eea20c6a0bf53aee5dc41db4f06d03b582459c3eaf892d0bd937f32c9da', '0e4a76e878aeb15a498e856dd8b8c7e32fa36fd35ff401a941f2152278270c9f')
 checker = checker.replace('033b04639076b7e8982504322c64443f167afd20', '51451adf1564de86e531b1de5a70f558d9bdb9b3')
 checker = checker.replace("const integration_candidate = '51451adf1564de86e531b1de5a70f558d9bdb9b3'", "const integration_candidate = '955b4af34bd668722631cef7926be5a0a22cec1e'")
 checker = checker.replace('semabi', 'semword').replace('SEMABI', 'SEMWORD')
 checker = checker.replace("wait := kind == 'wait'", "regression := kind == 'regression'")
 checker = checker.replace("if wait { 'SEMWAIT' } else { 'SEMWORD' }", "if regression { 'SEMABI' } else { 'SEMWORD' }")
 checker = checker.replace("if wait {\n\t\t'11163 failures=0'", "if regression {\n\t\t'175 failures=0'")
 checker = checker.replace('175 failures=90', '276 failures=89').replace("'175 failures=0'\n\t}", "'276 failures=0'\n\t}")
 checker = checker.replace('if baseline { 90 }', 'if baseline { 89 }')
 checker = checker.replace("['baseline', 'native', 'wait']", "['baseline', 'native']")
 checker = checker.replace("\n\t\t\tif kind != 'wait' {", "\n\t\t\t{")
 start := checker.index('\t\trequire(maintained.architecture') or { panic('Missing maintained section') }
 end := checker.index("\n\t}\n\tprintln('Native semaphore") or { panic('Missing audit end') }
 checker = checker[..start] + '		require(maintained.architecture == architecture && maintained.kernel_sha256 == kernel
			&& maintained.results.len == 2, "Wrong maintained runner identity")!
		mut seen := map[string]bool{}
		for result in maintained.results {
			require(result.name in ["semword", "semabi"] && result.name !in seen && result.exit_code == 0 && result.detail == "", "Maintained runner failed")!
			seen[result.name] = true
			require(result.source_sha256 == digest(root + "/source/fixture/" + result.name + "fixture/core.v")!
				&& result.init_sha256 == digest(path + "/maintained/" + result.name + "/init")!, "Different maintained fixture")!
			linked(root, manifest, result.source_inputs)!
			elf(os.read_bytes(path + "/maintained/" + result.name + "/init")!, suffix)!
			serial(os.read_file(path + "/maintained/" + result.name + "/serial.log")!, if result.name == "semabi" { "regression" } else { "native" })!
		}
		linked(root, manifest, json2.decode[map[string]string](os.read_file(path + "/maintained/controller-inputs.json")!)!)!' + checker[end..]
 checker = checker.replace('maintained runner and wait regression', 'maintained runner and 175-case ABI regression')
 checker = checker.replace('checks=175 failures=0\\nLINUX SEMWORD', 'checks=276 failures=0\\nLINUX SEMWORD').replace("good.replace('175', '174')", "good.replace('276', '275')")
 os.write_file(root + '/tests/linux-compat/semword-evidence.v', checker)!
}
