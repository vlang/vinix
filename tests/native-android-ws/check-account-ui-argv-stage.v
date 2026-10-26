// SPDX-License-Identifier: GPL-2.0-or-later
// Historical, read-only macOS checker; compile with V -new-compiler and run without arguments.
// Requires the original complete external bundles at the fixed paths below.
// Verifies host/stage evidence and retained module hash receipts; never launches a guest.
// This checker establishes no ART execution, Google account login or sign-in result.
module main

import json2
import os

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android'
const repo = '/Users/alex/code/vinix'
const check_root = state + '/account-ui-check-argv-2026-10-26-r1'
const stage_root = state + '/account-ui-stage-2026-10-26-r3'
const producer = state + '/current-ui-controller-build-2026-10-26-r1'
const seal = '503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a'
const controller = '5c5d6415f3e97cb2369187a7aa373aca019ae1e085298daf4551789739851f18'

struct Command {
    exit_code int
    output string
}

fn hash(path string) !string {
    mut f := os.open(path)!
    defer { f.close() }
    mut ctx := C.CC_SHA256_CTX{}
    assert C.CC_SHA256_Init(unsafe { &ctx }) == 1
    mut b := []u8{len: 1024 * 1024}
    for {
        n := f.read(mut b) or {
            if err is os.Eof { break }
            return err
        }
        if n == 0 { break }
        assert C.CC_SHA256_Update(unsafe { &ctx }, b.data, u32(n)) == 1
    }
    mut out := [32]u8{}
    assert C.CC_SHA256_Final(unsafe { &out[0] }, unsafe { &ctx }) == 1
    return out[..].hex()
}

fn doc(path string) !map[string]json2.Any {
    return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn string_map(v json2.Any) !map[string]string {
    return json2.decode[map[string]string](json2.encode(v))!
}

fn pins_valid(pins map[string]string) ! {
    for path, digest in pins {
        assert hash(path)! == digest, path
    }
}

fn inventory(root string, prefix string, mut result map[string]string) ! {
    for name in os.ls(root + '/' + prefix)! {
        rel := if prefix == '' { name } else { prefix + '/' + name }
        path := root + '/' + rel
        assert !os.is_link(path), path
        if os.is_dir(path) {
            inventory(root, rel, mut result)!
        } else {
            assert os.is_file(path), path
            if rel != 'sha256.json' { result[rel] = hash(path)! }
        }
    }
}

fn main() {
    review() or { eprintln(err); exit(1) }
}

fn review() ! {
    checks := doc(check_root + '/checks.json')!
    commands := json2.decode[[]Command](json2.encode(checks['checks']!))!
    assert commands.map(it.exit_code) == [0, 0, 0, 1, 0, 0]
    assert commands[1].output == commands[5].output
    assert commands[3].output.contains('requires embedded source bytes; compile with -prod')
    sources := string_map(checks['inputs_sha256']!)!
    mut live := map[string]string{}
    for name, digest in sources { live[repo + '/' + name] = digest }
    pins_valid(live)!
    host := doc(check_root + '/host/checks.json')!
    assert host['controller_build']!.str() == producer
    assert host['controller_build_sha256']!.str() == seal
    pins_valid(string_map(host['inputs_sha256']!)!)!
    assert hash(check_root + '/host/payload/bin/account-ui-guest')! == host['guest_sha256']!.str()
    println('HOST-RECEIPTS PASS source-inputs=' + sources.len.str())

    stage := doc(stage_root + '/stage.json')!
    assert stage['controller_build']!.str() == producer
    assert stage['controller_build_sha256']!.str() == seal
    assert hash(producer + '/sha256.json')! == seal
    assert hash(stage_root + '/controller-build/producer-sha256.json')! == seal
    assert stage['controller_source_revision']!.str() == 'c5fc9065af1e624002eaff6e2f927ce79858a06e'
    assert stage['helper_source_revision']!.str() == '4887c0f13'
    assert stage['compiled_stage_source_sha256']!.str() == sources['tests/native-android-ws/account-ui-stage.v']!
    assert stage['compiled_guest_source_sha256']!.str() == sources['tests/native-android-ws/account-ui-guest.v']!
    for name, digest in {
        'account-ui-controller': controller
        'account-ui-guest': host['guest_sha256']!.str()
        'vinix-android-account-ui': 'eff0ee8da211772f2549a5b39fdb2739cbb746db44e859bc25bd56b854fbd989'
    } { assert hash(stage_root + '/payload/bin/' + name)! == digest }
    assert hash(stage_root + '/efivars.fd')! == stage['staged_efivars_sha256']!.str()
    assert hash(stage_root + '/boot.img')! == stage['staged_boot_sha256']!.str()
    before := string_map(stage['original_modules_sha256']!)!
    after := string_map(stage['preserved_modules_sha256']!)!
    assert before.len == 6 && before == after
    for name, digest in before {
        assert os.read_file(stage_root + '/commands/original-' + name + '.sha256')!.fields()[0] == digest
        assert os.read_file(stage_root + '/commands/preserved-' + name + '.sha256')!.fields()[0] == digest
    }
    closure := json2.decode[map[string]string](os.read_file(producer + '/account-ui-controller-compiled-closure.json')!)!
    for path, digest in closure {
        assert path.starts_with(producer + '/closure/account-ui-controller/')
        assert hash(stage_root + '/controller-build/' + path[producer.len + 1..])! == digest
    }
    expected := json2.decode[map[string]string](os.read_file(stage_root + '/sha256.json')!)!
    mut actual := map[string]string{}
    inventory(stage_root, '', mut actual)!
    assert actual == expected
    pins_valid(string_map(stage['inputs_sha256']!)!)!
    println('STAGE-REVIEW PASS complete-inventory=' + actual.len.str() + ' source-inputs=' + string_map(stage['inputs_sha256']!)!.len.str() + ' firmware payload provenance six-preserved-modules-receipts')
}
