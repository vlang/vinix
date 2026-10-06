// SPDX-License-Identifier: GPL-2.0-or-later
module plist

import encoding.hex
import os

fn fixture() []u8 {
    return hex.decode("62706c6973743030d40102030405060b0e55427974657355466c616773564e6573746564555363656e6543616263a40708090a090813ffffffffffffffd6234009000000000000d10c0d5556616c75655561726d3634632705d83dde800811171d242a2e3334353e474a50560000000000000101000000000000000f0000000000000000000000000000005d") or { panic(err) }
}

fn test_binary_unicode_types_and_nested_dictionary() {
    value := parse(fixture())!
    defer { value.free() }
    assert value.kind == .dictionary
    assert value.fields['Scene'].text == '✅🚀'
    flags := value.fields['Flags'].values
    assert flags[0].boolean && !flags[1].boolean
    assert flags[2].integer == -42
    assert flags[3].real == 3.125
    assert value.fields['Bytes'].data == 'abc'.bytes()
    assert value.fields['Nested'].fields['Value'].text == 'arm64'
}

fn test_xml_dictionary_array_and_types() {
    text := '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Unicode</key><string>✅🚀</string><key>Values</key><array><true/><false/><integer>-42</integer><real>3.125</real><data>YWJj</data></array></dict></plist>'
    value := parse(text.bytes())!
    defer { value.free() }
    assert value.fields['Unicode'].text == '✅🚀'
    items := value.fields['Values'].values
    assert items[0].boolean && !items[1].boolean
    assert items[2].integer == -42 && items[3].real == 3.125
    assert items[4].data == 'abc'.bytes()
}

fn test_binary_rejects_truncated_and_invalid_tables() {
    original := fixture()
    for n in 1 .. original.len {
        if value := parse(original[..n]) { value.free(); assert false, 'truncated binary accepted' }
    }
    for index in [original.len - 26, original.len - 25, original.len - 1] {
        mut invalid := original.clone()
        invalid[index] = 0xff
        if value := parse(invalid) { value.free(); assert false, 'invalid binary table accepted' }
    }
}

fn test_rejects_entities_duplicate_keys_and_excessive_depth() {
    for text in [
        '<!DOCTYPE plist [<!ENTITY x "bad">]><plist><string>&x;</string></plist>',
        '<plist><dict><key>x</key><true/><key>x</key><false/></dict></plist>',
        '<plist>' + '<array>'.repeat(70) + '<true/>' + '</array>'.repeat(70) + '</plist>',
        '<plist><true/><false/></plist>',
        '<plist><integer><true/></integer></plist>',
        '<plist><true>invalid</true></plist>',
        '<plist><data>abc!====</data></plist>',
        '<plist><string>&unknown;</string></plist>',
        '<plist><true/></plist><plist><false/></plist>',
    ] {
        if value := parse(text.bytes()) { value.free(); assert false }
    }
}

fn test_xml_entities_cdata_and_whitespace_in_data() {
    value := parse('<plist><array><string>&amp;amp; &#x1F680; <![CDATA[<literal>]]></string><data> YW\nJj </data></array></plist>'.bytes())!
    defer { value.free() }
    assert value.values[0].text == '&amp; 🚀 <literal>'
    assert value.values[1].data == 'abc'.bytes()
}

fn test_xml_preserves_string_key_whitespace_and_mixed_text_order() {
    value := parse('<plist><dict><key> spaced key </key><string> \tfirst<!--ignored--><![CDATA[&second]]> third\n </string></dict></plist>'.bytes())!
    defer { value.free() }
    assert value.fields[' spaced key '].text == ' \tfirst&second third\n '
}

fn test_xml_serialization_round_trip_unicode_escaping_and_data() {
    original := parse(fixture())!
    defer { original.free() }
    encoded := encode_xml(original)!
    value := parse(encoded.bytes())!
    defer { value.free() }
    assert value.fields['Scene'].text == '✅🚀'
    assert value.fields['Bytes'].data == 'abc'.bytes()
    assert value.fields['Flags'].values[2].integer == -42
    assert value.fields['Flags'].values[3].real == 3.125
    escaped := encode_xml(Value{kind: .string, text: '&<✅🚀>'})!
    assert escaped.contains('&amp;&lt;✅🚀&gt;')
    parsed := parse(escaped.bytes())!
    defer { parsed.free() }
    assert parsed.text == '&<✅🚀>'
}

fn test_upstream_ppsspp_info_when_available() {
    path := os.getenv('VINIX_IOS_PPSSPP_PLIST')
    if path == '' { return }
    value := parse(os.read_bytes(path)!)!
    defer { value.free() }
    assert value.fields['CFBundleIdentifier'].text == 'org.ppsspp.ppsspp'
    manifest := value.fields['UIApplicationSceneManifest']
    scenes := manifest.fields['UISceneConfigurations'].fields['UIWindowSceneSessionRoleApplication'].values
    assert scenes[0].fields['UISceneDelegateClassName'].text == 'SceneDelegate'
}
