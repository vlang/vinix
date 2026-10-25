// SPDX-License-Identifier: GPL-2.0-or-later
// Extract unchanged Maps callers and retain the pinned ART verifier mechanism.
module main

import crypto.sha256
import json2
import net.http
import os
import time

const self = 'tests/native-android-ws/maps-video-verifier-sourceproof.v'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const cc_pin = '179301dcb41ea78accc3fa0048a7e6f6710d891945a751a34addd622020c1818'
const origin = '/Users/alex/.local/state/vinix/android/maps335-2026-10-25'
const origin_pin = '8d493e4588b6b3af87316824809f902bb50aac577b0e58e95d435ae02f2e137a'
const apk = origin + '/prelaunch/inputs/build/android-maps/GoogleMaps.apk'
const apk_pin = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'
const serial = '/Users/alex/.local/state/vinix/android/maps347-2026-10-25/results/attempt347/google-maps/serial.log'
const serial_pin = 'ad3c6ac0173f4a8885fb0f184967eaa1177b40554f7472b62bcd8e0616a41cd9'
const framework = '/Users/alex/.local/state/vinix/android/superscript-span346-2026-10-25'
const framework_manifest_pin = '6d5205fce48faea0c406efb68ec9134c039aa106e591d20e4501f2826d65064b'
const framework_pin = 'b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const revision = 'e78bf68917bcaaf58fef3960cd88793b3b7f39cc'
const remote = 'https://gitlab.com/android_translation_layer/art_standalone/-/raw/' + revision + '/art/runtime/verifier/method_verifier.cc'
const classes = ['hqa', 'hwv', 'hgm', 'hit', 'hiu', 'hiq', 'hxf']

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		digest.write(buffer[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn save[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular evidence: ' + key) }
		}
	}
}

fn record(out string, label string, argv []string) !string {
	started := time.utc().str()
	pin := hash(os.real_path(argv[0]))!
	r := os.exec(argv)
	os.write_file(out + '/' + label + '.log', r.output)!
	save(out + '/' + label + '.json', {
		'argv': json2.Any(argv), 'started_utc': json2.Any(started),
		'completed_utc': json2.Any(time.utc().str()),
		'executable_sha256': json2.Any(pin), 'exit_code': json2.Any(r.exit_code),
	})!
	assert hash(os.real_path(argv[0]))! == pin
	assert r.exit_code == 0, label + ': ' + r.output
	return r.output
}

fn contracts(out string) ! {
	assert hash(out + '/framework346-origin-sha256.json')! == framework_manifest_pin
	assert hash(out + '/framework346.jar')! == framework_pin
	listed := os.read_file(out + '/framework346-classes.log')!.split_into_lines()
	assert 'Landroid/media/MediaCodec;' in listed
	for name in ['MediaCodec$CryptoException', 'MediaCodec$CodecException', 'MediaCryptoException'] {
		assert 'Landroid/media/' + name + ';' !in listed, name
	}
	assert hash(out + '/apk-origin-sha256.json')! == origin_pin
	original := json2.decode[map[string]string](os.read_file(out + '/apk-origin-sha256.json')!)!
	assert original['inputs/build/android-maps/GoogleMaps.apk']! == apk_pin
	assert hash(out + '/serial.log')! == serial_pin
	assert os.read_file(out + '/serial.log')!.contains('hqa.V(long, long): [0x4CF] copy1 v5<-v3 type=Undefined cat=1')
	assert hash(out + '/selected/hqa.smali')! == 'b308cabfaed84825b961b0f24c52e0f2e58f21780de9a94abf974f545b0ecf1f'
	hqa := os.read_file(out + '/selected/hqa.smali')!.fields().join(' ')
	for text in [
		'.method public V(JJ)V .registers 35',
		'#@4cf .line 1232 :goto_4cf move v5, v3',
		'#@4d3 .line 1236 :catch_4d3 move-exception v0 #@4d4 .line 1237 const/4 v3, 0x0',
		'.catch Landroid/media/MediaCodec$CryptoException; {:try_start_6f .. :try_end_75} :catch_4d3',
		'.catch Ljava/lang/IllegalStateException; {:try_start_4c2 .. :try_end_534} :catch_784',
		'#@784 .line 1925 :catch_784 move-exception v0 #@785 .line 1926 goto/16 :goto_4cf',
		'Landroid/media/MediaCodec$CryptoException;->getErrorCode()I',
		'Landroid/media/MediaCodec$CodecException;->getDiagnosticInfo()Ljava/lang/String;',
	] { assert hqa.contains(text), text }
	// The move-exception at 4d3 is itself inside the outer protected interval.
	start := hqa.index(':try_start_4c2') or { return error('missing outer try') }
	inner := hqa.index(':catch_4d3 move-exception') or { return error('missing inner handler') }
	end := hqa.index(':try_end_534') or { return error('missing outer try end') }
	assert start < inner && inner < end
	for name in ['hqa', 'hgm', 'hit', 'hiu', 'hiq', 'hxf'] {
		assert !os.read_file(out + '/selected/' + name + '.smali')!.contains('<clinit>')
	}
	hwv := os.read_file(out + '/selected/hwv.smali')!.fields().join(' ')
	assert hwv.contains('.super Lhqa;') && hqa.contains('.super Lhgm;')
	init := hwv.all_after('.method static constructor <clinit>()V').all_before('.end method')
	assert init.contains('new-array v0, v0, [I') && init.contains('sput-object v0, Lhwv;->n:[I')
	assert !init.contains('invoke-')
	assert hash(out + '/method_verifier.cc')! == 'b14bd1b86eadbab6f3ed9f161ff24b98ffa9a3214ec177d85d369989a20ca13a'
	art := os.read_file(out + '/method_verifier.cc')!.fields().join(' ')
	for text in [
		'case Instruction::MOVE_EXCEPTION:', 'const RegType& res_type = GetCaughtExceptionType();',
		'ResolveClass<CheckAccess::kYes>(iterator.GetHandlerTypeIndex());',
		'Fail(VERIFY_ERROR_NO_CLASS) << "unresolved exception class " << exception;',
		'have_pending_runtime_throw_failure_ = true;',
		'if ((opcode_flags & Instruction::kThrow) == 0 && GetInstructionFlags(work_insn_idx_).IsInTry()) { saved_line_->CopyFromLine(work_line_.get());',
		'} else if (have_pending_runtime_throw_failure_) {', 'opcode_flags = Instruction::kThrow;',
		'if ((opcode_flags & Instruction::kThrow) != 0 && GetInstructionFlags(work_insn_idx_).IsInTry()) {',
		'CatchHandlerIterator iterator(code_item_accessor_, *try_item);',
		'if (!UpdateRegisters(iterator.GetHandlerAddress(), saved_line_.get(), false)) {',
	] { assert art.contains(text), text }
	assert os.read_file(out + '/build-art.sh')!.contains('COMMIT=' + revision)
	assert os.ls(out + '/selected')!.sorted() == classes.map(it + '.smali').sorted()
}

fn gather(out string) ! {
	assert hash(origin + '/prelaunch-sha256.json')! == origin_pin && hash(apk)! == apk_pin
	assert hash(serial)! == serial_pin
	os.cp(origin + '/prelaunch-sha256.json', out + '/apk-origin-sha256.json')!
	os.cp(serial, out + '/serial.log')!
	os.cp('build-support/android/build-art.sh', out + '/build-art.sh')!
	assert hash(framework + '/sha256.json')! == framework_manifest_pin
	assert hash(framework + '/framework/api-impl.jar')! == framework_pin
	os.cp(framework + '/sha256.json', out + '/framework346-origin-sha256.json')!
	os.cp(framework + '/framework/api-impl.jar', out + '/framework346.jar')!
	started := time.utc().str()
	response := http.get(remote)!
	assert response.status_code == 200, response.status_code.str()
	os.write_file(out + '/method_verifier.cc', response.body)!
	os.write_file(out + '/method-verifier-http-headers.txt', response.header.str())!
	save(out + '/method-verifier-http.json', {
		'url': json2.Any(remote), 'revision': json2.Any(revision),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'http_status': json2.Any(response.status_code), 'bytes': json2.Any(response.body.len),
		'sha256': json2.Any(hash(out + '/method_verifier.cc')!),
	})!
	os.mkdir_all(out + '/tools/jars')!
	os.mkdir_all(out + '/selected')!
	mut inputs := {apk: apk_pin, java: hash(java)!, serial: serial_pin}
	os.cp(java, out + '/tools/java')!
	for name in ['baksmali-2.5.2.jar', 'dexlib2-2.5.2.jar', 'util-2.5.2.jar',
		'guava-27.1-android.jar', 'jcommander-1.64.jar', 'failureaccess-1.0.1.jar'] {
		path := os.abs_path('build/android-framework/tools/' + name)
		inputs[path] = hash(path)!
		os.cp(path, out + '/tools/jars/' + name)!
		assert hash(out + '/tools/jars/' + name)! == inputs[path]!
	}
	record(out, 'extract', [java, '-cp', out + '/tools/jars/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', '--classes', classes.map('L' + it + ';').join(','),
		'--code-offsets', '-o', out + '/selected', apk + '/classes4.dex'])!
	record(out, 'framework346-classes', [java, '-cp', out + '/tools/jars/*',
		'org.jf.baksmali.Main', 'list', 'classes', out + '/framework346.jar'])!
	for path, pin in inputs { assert hash(path)! == pin, path }
	save(out + '/inputs.json', inputs)!
	save(out + '/apk-reference.json', {'canonical_path': apk, 'sha256': apk_pin,
		'origin_manifest_sha256': origin_pin, 'dex_entry': 'classes4.dex',
		'preservation': 'Original canonical APK remains external; no rewriting or APK copy.'})!
	contracts(out)!
}

fn capture(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh external directory required'
	assert hash(compiler)! == compiler_pin && hash('/usr/bin/cc')! == cc_pin
	os.mkdir_all(out + '/compiler-inputs')!
	os.cp(self, out + '/author.v')!
	os.cp(os.executable(), out + '/bootstrap')!
	before := hash(self)!
	record(out, 'checkout-revision', ['/usr/bin/git', 'rev-parse', 'HEAD'])!
	record(out, 'compiler-version', [compiler, 'version'])!
	record(out, 'cc-version', ['/usr/bin/cc', '--version'])!
	closure := record(out, 'compiler-closure', [compiler, '-print-v-files', self])!
	mut inputs := map[string]string{}
	for path in closure.split_into_lines().filter(it.ends_with('.v')) {
		inputs[path] = hash(path)!
		target := out + '/compiler-inputs/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
	}
	assert inputs.len > 0
	save(out + '/compiler-inputs.json', inputs)!
	os.mkdir_all(out + '/generated-c')!
	os.setenv('VTMP', out + '/generated-c', true)
	record(out, 'compile-author', [compiler, '-nocache', '-keepc', '-showcc', '-cc', '/usr/bin/cc',
		'-o', out + '/author', self])!
	for path, pin in inputs { assert hash(path)! == pin, path }
	assert hash(self)! == before && hash(compiler)! == compiler_pin
	assert hash('/usr/bin/cc')! == cc_pin
	record(out, 'gather', [out + '/author', 'gather', out])!
	save(out + '/compiler.json', {'path': compiler, 'sha256': compiler_pin,
		'cc_path': '/usr/bin/cc', 'cc_sha256': cc_pin})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	save(out + '/sha256.json', pins)!
	println('MAPS-VIDEO-VERIFIER-SEALED ' + hash(out + '/sha256.json')!)
}

fn verify(out string, seal string, receipt string) ! {
	assert !os.exists(receipt) && !receipt.starts_with(out + '/')
	assert hash(out + '/sha256.json')! == seal
	pins := json2.decode[map[string]string](os.read_file(out + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(out, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == pins && pins.len > 100, 'complete original bundle required'
	contracts(out)!
	save(receipt, {'result': 'PASS', 'manifest_sha256': seal, 'bundle': out, 'files': pins.len.str()})!
	println('MAPS-VIDEO-VERIFIER-READBACK-PASS ' + pins.len.str())
}

fn main() {
	$if prod { panic('requires assertions') }
	assert os.args.len >= 3, 'capture FRESH_OUTPUT | verify BUNDLE MANIFEST RECEIPT'
	match os.args[1] {
		'capture' { assert os.args.len == 3; capture(os.abs_path(os.args[2]))! }
		'gather' { assert os.args.len == 3; gather(os.abs_path(os.args[2]))! }
		'verify' { assert os.args.len == 5; verify(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4]))! }
		else { panic('unknown command') }
	}
}
