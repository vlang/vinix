import os
fn main() {
 out := 'tests/android/results/2026-10-23/maps-window-insets'
 assert !os.exists(out)
 os.mkdir_all(out)!
 oldjar := '9f5ddfbb7a17cff8265c0c1a4dba752b59a9ac12e88801e15c26b17654f0c584'
 newjar := '68ad3466f9a8c84770fa0e40e39d1a3b0b6666f2b6d7ca67aeab53e6785e3aae'
 mut source := os.read_file('tests/android/results/2026-10-23/maps-texture-transform/retain.v')!
 source = source.replace('236', '239').replace('framework239-texture', 'framework239-insets')
 source = source.replace('maps-accessibility', 'maps-texture-transform').replace(oldjar, newjar)
 source = source.replace('framework_sources.len == 106 && previous_framework.len == 105', 'framework_sources.len == 108 && previous_framework.len == 106')
 source = source.replace('assert delta.len == 2', 'assert delta.len == 3')
 source = source.replace('source-delta-from235.json', 'source-delta-from236.json')
 source = source.replace("'tests/native-android-tools/androidtools/framework_texture_transforms.v'", "'tests/native-android-tools/androidtools/framework_insets.v',\n\t\t'tests/native-android-tools/androidtools/framework_lookup_trace.v'")
 source = source.replace("'suite159'", "'suite239-stream'")
 source = source.replace("'android/view/View.smali', 'android/view/TextureView.smali'", "'android/view/View.smali', 'android/view/TextureView.smali', 'android/view/WindowInsets.smali',\n\t\t'android/view/WindowInsets\$Builder.smali', 'android/view/WindowInsets\$Type.smali', 'android/graphics/Insets.smali'")
 start := source.index("\tfor name in ['build-native235.v',") or { panic('missing helper start') }
 end := source.index("\tfor name in ['native235-build.log',") or { panic('missing helper end') }
 source = source[..start] + "\tfor name in ['build-native235.v', 'prepare-framework239.v', 'build-framework239-insets.v',\n\t\t'snapshot-framework239.v', 'prepare239.v', 'run239.v', 'interact239.v', 'manual239.v',\n\t\t'identity239.v', 'verify-maps239-inputs.v', 'trace-input.v', 'prepare-maps239-receipt.v',\n\t\t'validate-module-stream.v', 'suite-low-disk.v', 'suite239-stream.v'] {\n\t\tcopy_file(base + name, out + '/helpers/' + name)!\n\t}\n\tfor name in ['pipeline.v.txt', 'prototype.v.txt', 'prototype.v', 'prepare.v', 'suite.diff',\n\t\t'sha256.json', 'final-sha256.json', 'prototype.log', 'root-proof.log', 'production-proof.log',\n\t\t'production-sources-sha256.json'] {\n\t\tcopy_file(base + 'stream238/' + name, out + '/streaming/' + name)!\n\t}\n\tfor path in ['build-support/android/modulestream/stream.v', 'build-support/android/modulestream/stream_test.v', 'tests/native-android-ws/suite.v'] {\n\t\tcopy_file(path, out + '/streaming/production/' + os.base(path))!\n\t}\n" + source[end..]
 source = source.replace("base + 'attempt239-prelaunch-failure/'", "base + 'attempt238-prelaunch-failure/'")
 source = source.replace('The initial Maps239 attempt failed', 'Maps238 failed').replace('The completed run in this receipt is a retry with identical framework/native/APK inputs; this staging failure is retained separately from the application outcome.', 'Maps239 subsequently uses corrected framework239 and the streaming harness with unchanged native235 and APK inputs. This staging failure is retained separately from the application outcome.')
 source = source.replace('Maps239 uses the independently tested native235 path precision implementation and framework239 TextureView content transform state.', 'Maps239 uses native235 path precision, framework239 WindowInsets value/Builder APIs, the framework237 narrow optional-class lookup trace, and the independently tested streaming module staging helper.')
 source = source.replace('Retain raw results', 'Retain raw results')
 os.write_file(out + '/retain.v', source)!
 mut validator := os.read_file('tests/android/results/2026-10-23/maps-texture-transform/validate.v')!
 validator = validator.replace('236', '239').replace('framework239-texture', 'framework239-insets').replace('maps-accessibility', 'maps-texture-transform').replace(oldjar, newjar)
 validator = validator.replace('framework.len == 106 && previous_framework.len == 105', 'framework.len == 108 && previous_framework.len == 106')
 validator = validator.replace('source-delta-from235.json', 'source-delta-from236.json')
 validator = validator.replace("'tests/native-android-tools/androidtools/framework_texture_transforms.v'", "'tests/native-android-tools/androidtools/framework_insets.v',\n\t\t\t'tests/native-android-tools/androidtools/framework_lookup_trace.v'")
 validator = validator.replace('changed == 2 && delta.len == 2', 'changed == 3 && delta.len == 3').replace("'build/android-maps/suite159'", "'build/android-maps/suite239-stream'").replace("files['suite159']", "files['suite239-stream']")
 validator = validator.replace("assert os.read_file(out + '/prelaunch-failure/run.log')!.contains(files['framework239-insets/api-impl.jar']!.str())", "assert os.read_file(out + '/prelaunch-failure/run.log')!.contains('APK-SUITE boot google-maps')")
 validator = validator.replace('assert smali.len == 16', 'assert smali.len == 20')
 oldchecks := validator.index("\t\tassert result['outcome']!.str() == 'startup_failed'") or { panic('missing prior result checks') }
 obs := validator.index("\t\tassert os.exists(out + '/observations.json')") or { panic('missing observations') }
 validator = validator[..oldchecks] + "\t\tassert result['outcome']!.str().len > 0\n\t\tassert serial.len > 0\n" + validator[obs..]
 insert := validator.index("\tif os.args[1] == 'result' {") or { panic('missing result branch') }
 validator = validator[..insert] + "\tassert smali['android/view/WindowInsets\$Builder.smali'].contains('build()Landroid/view/WindowInsets;')\n\tassert smali['android/view/WindowInsets.smali'].contains('getInsets(I)Landroid/graphics/Insets;')\n\tassert smali['android/view/WindowInsets\$Type.smali'].contains('systemOverlays()I')\n\tassert smali['android/graphics/Insets.smali'].contains('of(IIII)Landroid/graphics/Insets;')\n\tassert os.read_file(out + '/streaming/prototype.log')!.contains('STREAM238 ALL PASS')\n\tassert os.read_file(out + '/streaming/root-proof.log')!.contains('STREAM238 ALL PASS')\n\tassert os.read_file(out + '/streaming/production-proof.log')!.contains('1 passed, 1 total')\n" + validator[insert..]
 os.write_file(out + '/validate.v', validator)!
 println('MAPS239 receipt helpers prepared; actual outcome deliberately pending')
}
