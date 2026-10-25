// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time

fn digest(path string) !string {
    return sha256.sum(os.read_bytes(path)!).hex()
}

fn write[T](path string, value T) ! {
    os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn main() {
    root := '/Users/alex/.local/state/vinix/android/maps295-2026-10-25'
    output := '/Users/alex/.local/state/vinix/android/maps295-result-audit2-2026-10-25'
    compiler := 'build/android-maps/queue284-tools/v_old276'
    source := 'tests/native-android-ws/maps295-result-audit.v'
    binary := 'build/android-maps/maps295-result-audit'
    if os.args.len == 2 && os.args[1] == 'build' {
        if os.exists(output) { panic('fresh audit destination required') }
        assert digest(compiler)! == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
        os.mkdir(output)!
        os.cp(source, output + '/audit.v')!
        argv := [compiler, '-nocache', '-cc', 'cc', '-cflags', '-O2', '-o', binary, source]
        started := time.utc().str()
        result := os.exec(argv)
        os.write_file(output + '/build.log', result.output)!
        write(output + '/build-receipt.json', {
            'argv': json2.Any(argv)
            'started_utc': json2.Any(started)
            'completed_utc': json2.Any(time.utc().str())
            'exit_code': json2.Any(result.exit_code)
            'source_sha256': json2.Any(digest(source)!)
            'compiler_sha256': json2.Any(digest(compiler)!)
        })!
        if result.exit_code != 0 { panic('audit build failed') }
        os.cp(binary, output + '/audit')!
        println('MAPS295-AUDIT-BUILD-PASS')
        return
    }
    if os.args.len != 2 || os.args[1].len != 64 { panic('usage: audit build | FINAL295_SHA256') }
    if os.exists(output + '/sha256.json') { panic('sealed audit output must remain unchanged') }
    assert digest(root + '/sha256.json')! == os.args[1]
    manifest := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
    serial_key := 'results/attempt295/google-maps/serial.log'
    results_key := 'results/attempt295/results.json'
    for key in [serial_key, results_key] { assert digest(root + '/' + key)! == manifest[key]! }
    serial := os.read_file(root + '/' + serial_key)!
    patterns := {
        'missing_png': 'No implementation found for byte[] android.graphics.Bitmap.native_save_to_png(long)'
        'unsatisfied_link': 'UnsatisfiedLinkError'
        'fatal_exception': 'FATAL EXCEPTION'
        'runtime_aborting': 'Runtime aborting'
        'jni_detected_error': 'JNI DETECTED ERROR'
        'out_of_memory': 'OutOfMemoryError'
        'sigsegv': 'SIGSEGV'
        'path_dot_op': 'Path.op'
        'path_native_op': 'android.graphics.Path.native_op'
        'stub_op': 'STUB: op'
        'process_exit': 'APK-SUITE-EXIT id='
        'android_ws_fail': 'ANDROID-WS-FAIL'
        'suite_dependency_fail': 'APK-SUITE-DEPENDENCY-FAIL'
        'ws_dependency_fail': 'ANDROID-WS-DEPENDENCY-FAIL'
        'ws_process_fail': 'ANDROID-WS-PROCESS-FAIL'
        'no_class_def': 'NoClassDefFoundError'
        'no_such_method': 'NoSuchMethodError'
        'class_not_found': 'ClassNotFoundException'
        'no_such_field': 'NoSuchFieldError'
    }
    mut counts := map[string]int{}
    for key, pattern in patterns {
        counts[key] = serial.split_into_lines().filter(it.contains(pattern)).len
    }
    lines := serial.split_into_lines()
    mut path_pairs := 0
    for i, line in lines {
        if i > 0 && line.trim_space() == 'STUB: op' && lines[i - 1].trim_space() == 'Path' {
            path_pairs++
        }
    }
    counts['path_op_warning_pairs'] = path_pairs
    write(output + '/line-counts.json', counts)!
    write(output + '/patterns.json', patterns)!
    os.cp(root + '/' + results_key, output + '/results.json')!
    write(output + '/references.json', {
        'completed_root': root
        'completed_manifest_sha256': os.args[1]
        'serial_key': serial_key
        'serial_sha256': manifest[serial_key]!
        'results_key': results_key
        'results_sha256': manifest[results_key]!
        'audit_source_sha256': digest(source)!
        'audit_binary_sha256': digest(binary)!
        'completed_utc': time.utc().str()
        'count_definition': 'Number of final sealed raw serial lines containing each case-sensitive literal pattern; path_op_warning_pairs counts adjacent trimmed lines Path then STUB: op.'
    })!
    mut inventory := map[string]string{}
    for name in os.ls(output)! { inventory[name] = digest(output + '/' + name)! }
    write(output + '/sha256.json', inventory)!
    println('MAPS295-AUDIT-PASS seal=' + digest(output + '/sha256.json')!)
    println(json2.encode(counts))
}
