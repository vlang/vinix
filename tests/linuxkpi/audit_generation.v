// SPDX-License-Identifier: GPL-2.0-or-later
module main
import auditfixture
import fixturehost
import hosttest
import json2
import os
fn main() {
 if os.args.len == 3 && os.args[1] == '--install-query' { fixturehost.install(os.args[2]) or { eprintln(err); exit(1) }; return }
 row := hosttest.decode_json(os.get_raw_line()) or { eprintln(err); exit(1) }.as_map()
 auditfixture.fixture(row['name'] or { json2.Any('') }.str(), row['python'] or { json2.Any('') }.str()) or {
  value := if err is auditfixture.BindingFailure { err.value } else { {'kind': json2.Any('RuntimeError'), 'message': json2.Any(err.msg())} }
  println(json2.encode({'error': json2.Any(value)}, escape_unicode: true)); return
 }
 println(json2.encode({'value': json2.Any(json2.Null{})}))
}
