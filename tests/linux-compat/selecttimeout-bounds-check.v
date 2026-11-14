// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the exact pure fixture helper, without the Linux-only fixture ABI.
module main

import crypto.sha256
import json2
import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: selecttimeout-bounds-check V-COMPILER FRESH-STATE') }
	compiler := os.real_path(os.args[1])
	state := os.args[2]
	if os.exists(state) { return error('Fresh state required') }
	os.mkdir_all(state)!
	source := os.dir(@FILE)+'/selecttimeoutfixture/bounds.v'
	helper := os.read_file(source)!
	if helper.count('module selecttimeoutfixture') != 1 { return error('Different bounds module') }
	// Tuple: seconds, subsecond, original duration ns, enclosing elapsed ns,
	// ABI unit ns, expected validity. These include coincident clock samples,
	// observable timeval normalization, lower/upper bounds and signed limits.
	controls := '
fn main() {
 cases := [
  [i64(0),500000,500000000,0,1000,1]!,
  [i64(0),500000000,500000000,0,1,1]!,
  [i64(1),500000,1500000000,0,1000,1]!,
  [i64(0),499999,500000000,1,1000,1]!,
  [i64(0),499999999,500000000,1,1,1]!,
  [i64(0),0,500000000,500000000,1,1]!,
  [i64(0),0,0,0,1000,1]!,
  [i64(0),0,1,0,1000,1]!,
  [i64(9223372036),854775807,9223372036854775807,0,1,1]!,
  [i64(0),0,1,9223372036854775807,1000,1]!,
  [i64(0),500001,500000000,1000000,1000,0]!,
  [i64(0),1500000,1500000000,0,1000,0]!,
  [i64(0),499998,500000000,1,1000,0]!,
  [i64(0),499999998,500000000,1,1,0]!,
  [i64(0),0,500000000,499999999,1,0]!,
  [i64(-1),0,500000000,0,1,0]!,
  [i64(0),-1,500000000,0,1,0]!,
  [i64(0),1000000000,1000000000,0,1,0]!,
  [i64(0),1000000,1000000000,0,1000,0]!,
  [i64(0),0,-1,0,1,0]!,
  [i64(0),0,0,-1,1,0]!,
  [i64(0),0,0,0,0,0]!,
  [i64(0),0,0,0,1000000,0]!,
  [i64(9223372036854775807),0,9223372036854775807,0,1,0]!,
  [i64(9223372036),854775808,9223372036854775807,0,1,0]!,
  [i64(1),0,999999999,0,1,0]!,
 ]!
 mut positive := 0
 mut negative := 0
 for c in cases {
  found := remaining_within_bounds(c[0],c[1],c[2],c[3],c[4])
  if found != (c[5] == 1) { panic("Incorrect remaining-time control: "+c.str()) }
  if found { positive++ } else { negative++ }
 }
 println("Select timeout bounds: PASS ("+positive.str()+" positive, "+negative.str()+" negative controls)")
}
'
	os.write_file(state+'/main.v',helper.replace('module selecttimeoutfixture','module main')+controls)!
	command := [compiler,'-cc','cc','-cflags','-O2','-o',state+'/control',state+'/main.v']
	os.write_file(state+'/command.json',json2.encode(command,prettify:true)+'\n')!
	built := os.exec(command)
	os.write_file(state+'/compile.log',built.output)!
	if built.exit_code != 0 { return error(built.output) }
	checked := os.exec([state+'/control'])
	os.write_file(state+'/controls.log',checked.output)!
	os.write_file(state+'/receipt.json',json2.encode({
		'source':sha256.sum(helper.bytes()).hex(),
		'controller':sha256.sum(os.read_bytes(@FILE)!).hex(),
		'compiler':sha256.sum(os.read_bytes(compiler)!).hex(),
		'generated':sha256.sum(os.read_bytes(state+'/main.v')!).hex(),
		'control':sha256.sum(os.read_bytes(state+'/control')!).hex(),
		'status':checked.exit_code.str(),
	},prettify:true)+'\n')!
	if checked.exit_code != 0 { return error(checked.output) }
	print(checked.output)
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
