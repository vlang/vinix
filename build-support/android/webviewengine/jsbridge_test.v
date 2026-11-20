// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browseripc
import os

fn test_bridge_script_defines_only_registered_methods() {
	interfaces := browseripc.parse_js_interfaces('mm getAndroidId addAccount\nother ping'.bytes()) or {
		panic(err)
	}
	script := js_bridge_script('00ff', interfaces)
	assert script.contains('marker="\\u0001vinix-bridge:00ff"')
	assert script.contains('"mm":["getAndroidId","addAccount"]')
	assert script.contains('"other":["ping"]')
	assert script.starts_with('(function(){') && script.ends_with('})();')
	assert js_bridge_allowed(interfaces, 'mm', 'addAccount')
	assert !js_bridge_allowed(interfaces, 'mm', 'ping')
	assert !js_bridge_allowed(interfaces, 'absent', 'getAndroidId')
}

fn test_bridge_results_tag_values_and_exceptions() {
	assert js_bridge_result(0, '3:sab') == '=3:sab'
	assert js_bridge_result(0, '1:u') == '=1:u'
	assert js_bridge_result(1, 'Bad state') == '!Bad state'
	assert js_bridge_result(1, '') == '!Java exception'
}

// Runs the generated script in JavaScriptCore against a fake prompt playing
// the Android side: it decodes the tagged arguments and answers each method.
fn test_bridge_script_round_trips_in_javascript() {
	$if !macos {
		return
	}
	interfaces := browseripc.parse_js_interfaces('mm echo count flag nothing fail'.bytes()) or {
		panic(err)
	}
	harness := r'
var window = this, calls = [];
function decode(list) {
	var out = [], i = 0;
	while (i < list.length) {
		var c = list.indexOf(":", i), n = Number(list.slice(i, c));
		out.push(list.slice(c + 1, c + 1 + n)); i = c + 1 + n;
	}
	return out;
}
window.prompt = function (marker, body) {
	if (marker !== "\u0001vinix-bridge:t0") return "wrong marker";
	var p = body.split("\n"), args = decode(p.slice(2).join("\n"));
	calls.push(p[0] + "." + p[1] + "(" + args.join("|") + ")");
	if (p[1] === "echo") return "=" + args[0].length + ":" + args[0];
	if (p[1] === "count") return "=" + (1 + String(args.length).length) + ":n" + args.length;
	if (p[1] === "flag") return "=2:b1";
	if (p[1] === "nothing") return "=1:u";
	return "!boom";
};
' + js_bridge_script('t0', interfaces) + r'
var thrown = "";
try { mm.fail(); } catch (e) { thrown = e.message; }
var results = [mm.echo("hé😀", 5, true, null, undefined, {}), mm.count(1, 2, 3),
	mm.flag(), String(mm.nothing()), typeof mm.count(), thrown, typeof mm.missing];
JSON.stringify({results: results, calls: calls});
'
	path := os.join_path(os.temp_dir(), 'vinix-jsbridge-${os.getpid()}.js')
	os.write_file(path, harness) or { panic(err) }
	defer { os.rm(path) or {} }
	result := os.exec(['osascript', '-l', 'JavaScript', path])
	assert result.exit_code == 0, result.output
	expected := '{"results":["h\u00e9\U0001F600",3,true,"undefined","number","boom","undefined"],' +
		'"calls":["mm.fail()","mm.echo(sh\u00e9\U0001F600|n5|b1|z|u|u)","mm.count(n1|n2|n3)",' +
		'"mm.flag()","mm.nothing()","mm.count()"]}'
	assert result.output.trim_space() == expected, result.output
}
