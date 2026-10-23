import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
 artifacts map[string]string
 inputs map[string]string
 scope string
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
 out := os.dir(@FILE)
 b := 'build/android-maps/'
 task := b + 'canvas227/'
 mut inputs := map[string]string{}
 for variant in ['baseline', 'fixed'] {
  run := task + 'run-' + variant + '/'
  for pair in ['results.json|results.json', 'bootstrap-fixture/serial.log.gz|serial.log.gz',
   'bootstrap-fixture/application.png|application.png'] {
   parts := pair.split('|')
   os.cp(run + parts[0], out + '/' + variant + '-' + parts[1])!
  }
  os.cp(task + variant + '.json', out + '/' + variant + '-configuration.json')!
  os.cp(task + variant + '-harness.log', out + '/' + variant + '-harness.log')!
  for path in ['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
   'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so', 'usr/bin/run-android-calculator',
   'opt/android-test/native-guest'] {
   inputs[variant + '/staged/' + path] = hash(run + 'module/' + path)!
  }
  os.write_file_array(out + '/' + variant + '-Canvas.smali.gz', gzip.compress(os.read_bytes(task + 'verify-' + variant + '-smali/android/graphics/Canvas.smali')!)!)!
 }
 for source, name in {
  b + 'framework227-canvas-z/framework-manifest.json': 'framework-manifest.json'
  b + 'framework227-canvas-z/exact-sources.json.gz': 'framework-sources.json.gz'
  b + 'framework227-source-check.log': 'framework-source-check.log'
  b + 'canvas227-finalize.log': 'fixture-build.log'
  b + 'build-framework227-canvas-z.v': 'build-framework.v'
  b + 'finalize-canvas227.v': 'finalize-fixture.v'
  b + 'prepare-canvas227.v': 'prepare-fixture.v'
 } { os.cp(source, out + '/' + name)! }
 os.write_file_array(out + '/framework-build.log.gz', gzip.compress(os.read_bytes(b + 'framework227-canvas-z-build.log')!)!)!
 mut sources := map[string]string{}
 mut hashes := map[string]string{}
 for file in os.walk_ext(task + 'source/startupfixture', '.v') {
  name := os.base(file)
  source := os.read_file(file)!
  sources[name] = source
  hashes[name] = sha256.sum(source.bytes()).hex()
 }
 os.write_file_array(out + '/fixture-sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
 os.write_file(out + '/fixture-sources-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
 for path in ['framework226-filters/api-impl.jar', 'framework227-canvas-z/api-impl.jar',
  'libnative225.so', 'canvas227-apk/bootstrap.apk', 'suite159', 'launcher200'] {
  inputs[b + path] = hash(b + path)!
 }
 inputs['native-source-receipt/../maps-ws/attempt225-input-identities.json'] = hash(out + '/../maps-ws/attempt225-input-identities.json')!
 mut artifacts := map[string]string{}
 for name in os.ls(out)! {
  if name !in ['receipt.json', 'validation.log'] { artifacts[name] = hash(out + '/' + name)! }
 }
 os.write_file(out + '/receipt.json', json2.encode(Receipt{
  artifacts: artifacts
  inputs: inputs
  scope: 'Identical signed fixture/native225/launcher200 with framework226 versus227. Frozen framework sources differ only in software Canvas Z API additions;103 exact source identities verified. Fixture V sources are exact frozen inputs. Native source identities reuse the measured attempt225 receipt. Raw harness results are retained: native225 inherited Maps-only Future diagnostics print and clear fixture-irrelevant exceptions, which can classify a passing fixture as startup_failed. Probe markers plus READY establish fixture completion; no Maps functional success is claimed. Kernel/base receipts remain inherited; mutable shared boot images were not rehashed as source proof.'
 }, prettify: true) + '\n')!
 println('CANVAS-Z-RETAIN PASS ${artifacts.len} artifacts;${sources.len} frozen fixture sources;staged runtime identities')
}
