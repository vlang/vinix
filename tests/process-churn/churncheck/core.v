// SPDX-License-Identifier: GPL-2.0-or-later
module churncheck

import androidhost as ah

fn put(mapping string, key ah.Value, value string) ! { release([call('operator.setitem', o(mapping), key, o(value))!])! }
fn tuple_ids(values []string) !string { return call('_tuple', ...values.map(o(it)))! }
fn fail_text(message string) ! { fail('', [], message)! }
fn text_part(mut parts []string, text string) ! {
 value := literal(ah.Value(text)) or {release(parts.reverse())!; return err}
 parts << value
}
fn value_part(mut parts []string, id string) ! {
 value := formatted(id, false) or {release(parts.reverse())!; return err}
 parts << value
}
fn failure_parts(code string, args []string, text string) ![]string {
 mut parts := []string{}
 match code {
  'duplicate' { text_part(mut parts, 'duplicate ')!; value_part(mut parts,args[0])!; text_part(mut parts, ': ')!; value_part(mut parts,args[1])! }
  'program','measurement','cohort','grace','class','work','invalid_work','summary','overflow' {
   prefix := match code {
    'program' { 'unexpected program: ' }
    'measurement' { 'duplicate measurement: ' }
    'cohort' { 'wrong cohort size: ' }
    'grace' { 'duplicate grace: ' }
    'class' { 'invalid class: ' }
    'work' { 'duplicate workload evidence: ' }
    'invalid_work' { 'invalid workload evidence: ' }
    'summary' { 'duplicate allocation summary: ' }
    else { 'tracking overflow: ' }
   }
   text_part(mut parts,prefix)!; value_part(mut parts,args[0])!
  }
  'short' {text_part(mut parts,'short grace: ')!;value_part(mut parts,args[0])!;text_part(mut parts,': ')!;value_part(mut parts,args[1])!}
  'start' {text_part(mut parts,'expected one START/DONE, got ')!;value_part(mut parts,args[0])!;text_part(mut parts,'/')!;value_part(mut parts,args[1])!}
  'slab' {text_part(mut parts,'slabinfo retains 48-byte descriptors in cohort ')!;value_part(mut parts,args[0])!}
  'small' {text_part(mut parts,'16-byte operation objects do not settle: ')!;value_part(mut parts,args[0])!;text_part(mut parts,'/')!;value_part(mut parts,args[1])!}
  else {text_part(mut parts,text)!}
 }
 return parts
}
fn fail(code string, args []string, text string) ! {
 factory := global('ValueError')!
 parts := failure_parts(code,args,text) or {release([factory])!;return err}
 message := concatenate(parts) or {release([factory])!;return err}
 value := invoke_owned(factory, [o(message)], {}, [message])!
 call('_raise', o(value))!
 return error('ValueError callback returned')
}
fn fresh_dict() !string { return callback('literal', {'value': raw(ah.Value(map[string]ah.Value{}))})!.text() }
fn fresh_named(mut f Frame, name string) !string { return f.named(name, fresh_dict()!)! }
fn iterator(mut f Frame, value string, name string) !string {
 id := call('_ITER', o(value)) or { release([value])!; return err }
 release([value])!
 return f.named(name, id)!
}
fn next(id string) !string {
 value := callback('next', {'owner': ah.Value(id)})!.object()
 if ah.field(value, 'done') as bool { return '' }
 return ah.field(value, 'value').text()
}
fn forget(mut f Frame, name string) ! { if id := f.names[name] { f.names.delete(name); release([id])! } }
fn fields(line string, mut f Frame) !string {
 f.named('line', line)!
 result := fresh_named(mut f, 'result')!
 matches := call('re.findall', v(ah.Value(r'(\w+)=([^\s]+)'))!, o(line))!
 it := iterator(mut f, matches, '_iterator')!
 for {
  record := next(it)!
  if record == '' {break}
  values := pair(record)!
  key := f.named('key', values[0])!
  value := f.named('value', values[1])!
  if compare('contains', result, o(key))! { fail('duplicate', [key, line], '')! }
  put(result, o(key), value)!
  f.clean()!
 }
 forget(mut f, '_iterator')!
 return result
}
fn parsed_fields(line string, pins string) !string {
 start := checkpoint()!
 alias := call('_identity', o(line))!
 mut f := Frame{start:start,pins:pins,order:['line','result','key','value']}
 result := fields(alias,mut f) or {f.failed(err)!;return err}
 f.retire(result)!
 clean_since(start,[result])!
 return result
}
fn increment(mut f Frame, name string) ! { f.named(name, call('operator.add', o(f.names[name]), v(ah.Value(1))!)!)! }
fn starts(line string, text string) !bool { return tested(method(line, 'startswith', [v(ah.Value(text))!], {})!)! }
fn convert_row(row string, key string) !string {
 target := global('int')!
 raw_value := get(row, key) or { release([target])!; return err }
 result := invoke_owned(target, [o(raw_value)], {}, [raw_value])!
 put(row, v(ah.Value(key))!, result)!
 return result
}
fn any_generator(name string, arguments []ah.Value) !bool {
 target := global('any')!
 generated := call(name, ...arguments) or { release([target])!; return err }
 return tested(invoke_owned(target, [o(generated)], {}, [generated])!)!
}
fn integer_field(owner string, key string, radix ?int) !string {
 target := global('int')!
 value := get(owner,key) or {release([target])!;return err}
 args := if base:=radix {[o(value),v(ah.Value(base))!]}else{[o(value)]}
 return invoke_owned(target,args,{},[value])!
}
fn integer_item(owner string, key ah.Value) !string {
 target := global('int')!
 value := item(owner,key) or {release([target])!;return err}
 return invoke_owned(target,[o(value)],{},[value])!
}
fn inspect(ids []string, mut f Frame) !string {
 source := f.named('source', get(f.scope, 'source')!)!
 mode := f.named('mode', get(f.scope, 'mode')!)!
 flat_slabinfo := f.named('flat_slabinfo', get(f.scope, 'flat_slabinfo')!)!
 flat_small := f.named('flat_small', get(f.scope, 'flat_small')!)!
 cell := f.named('_line_cell', callback('literal', {'value': raw(ah.Value([none_()]))})!.text())!
 names := f.named('names', call('_cohort_names', o(mode))!)!
 measurements := fresh_named(mut f, 'measurements')!
 grace := fresh_named(mut f, 'grace')!
 live := fresh_named(mut f, 'live')!
 classes := fresh_named(mut f, 'classes')!
 work := fresh_named(mut f, 'work')!
 filesystems := fresh_named(mut f, 'filesystems')!
 f.named('starts', literal(ah.Value(0))!)!
 f.named('done', literal(ah.Value(0))!)!
 lines := method(source, 'splitlines', [], {})!
 it := iterator(mut f, lines, '_iterator')!
 for {
  incoming := next(it)!
  if incoming == '' {break}
  raw_line := f.named('raw', incoming)!
  line := method(raw_line, 'strip', [], {})!
  put(cell, v(ah.Value(0))!, line)!
  f.named('line', line)!
  if compare('eq', line, v(ah.Value('PROCESS CHURN: START'))!)! { increment(mut f, 'starts')! }
  if compare('eq', line, v(ah.Value('PROCESS CHURN: DONE failures=0'))!)! { increment(mut f, 'done')! }
  if any_generator('_failures', [o(cell)])! { fail_text_id(line)! }
  if starts(line, 'CHURN FILESYSTEM ')! {
   row := f.named('row', parsed_fields(line,f.pins)!)!
   program := get(row, 'program')!
   found := compare('contains', filesystems, o(program))!
   release([program])!
   if found { fail_text('duplicate filesystem evidence')! }
   kind := integer_field(row,'type',16)!
   put(filesystems, o(get(row, 'program')!), kind)!
  }
  if tested(method(line, 'startswith', [o(global('_PREFIXES')!)], {})!)! {
   row := f.named('row', parsed_fields(line,f.pins)!)!
   program := get(row, 'program')!
   target := global('int')!
   encoded := get(row, 'cohort')!
   cohort := invoke_owned(target, [o(encoded)], {}, [encoded])!
   identity := f.named('identity', tuple_ids([program, cohort])!)!
   release([cohort, program])!
   member := item(identity, v(ah.Value(0))!)!
   accepted := compare('contains', names, o(member))!
   release([member])!
   if !accepted { fail('program', [identity], '')! }
   if starts(line, 'CHURN MEASURE ')! {
    if compare('contains', measurements, o(identity))! { fail('measurement', [identity], '')! }
    for key in ['runs','used_delta_kib','cumulative_used_kib','slab_delta_kib','cumulative_slab_kib','cached_delta_kib','large_pages_delta'] {
     f.named('key', literal(ah.Value(key))!)!
     convert_row(row, key)!
    }
    count := f.named('count', literal(ah.Value(if compare('eq', mode, v(ah.Value('directories'))!)! { 200 } else { 300 }))!)!
    runs := get(row, 'runs')!
    wrong := compared('ne', runs, o(count))!
    if wrong { fail('cohort', [identity], '')! }
    put(measurements, o(identity), row)!
   } else if starts(line, 'CHURN GRACE ')! {
    if compare('contains', grace, o(identity))! { fail('grace', [identity], '')! }
    value := integer_field(row,'elapsed_ns',none)!
    put(grace, o(identity), value)!
    actual := item(grace, o(identity))!
    short := compared('lt', actual, v(ah.Value(i64(6000000000)))!)!
    if short { fail('short', [identity, item(grace, o(identity))!], '')! }
   } else if starts(line, 'CHURN CLASS ')! {
    size := f.named('size',integer_field(row,'size',none)!)!
    key := f.named('key', call('_class_key', o(identity), o(size))!)!
    if compare('le', size, v(ah.Value(0))!)! || compare('contains', classes, o(key))! { fail('class', [key], '')! }
    delta := integer_field(row,'objects_delta',none)!
    put(classes, o(key), delta)!
   } else if starts(line, 'CHURN WORK ')! {
    if compare('contains', work, o(identity))! { fail('work', [identity], '')! }
    value := integer_field(row,'elapsed_ns',none)!
    put(work, o(identity), value)!
    calls := integer_field(row,'calls',none)!
    invalid := compared('ne', calls, v(ah.Value(300))!)!
    if invalid || compared('lt', item(work, o(identity))!, v(ah.Value(0))!)! { fail('invalid_work', [identity], '')! }
   } else {
    matched := f.named('match', call('re.search', v(ah.Value(r' live (\d+) dropped (\d+)$'))!, o(line))!)!
    if truth(matched)! {
     if compare('contains', live, o(identity))! { fail('summary', [identity], '')! }
     value := integer_item(matched,v(ah.Value(1))!)!
     put(live, o(identity), value)!
     dropped := integer_item(matched,v(ah.Value(2))!)!
     overflow := tested(dropped)!
     if overflow { fail('overflow', [identity], '')! }
    }
   }
  }
  f.clean()!
 }
 forget(mut f, '_iterator')!
 expected := f.named('expected', call('_expected', o(names))!)!
 zero := call('_zero', o(names))!
 united := call('operator.or_', o(expected), o(zero)) or { release([zero])!; return err }
 release([zero])!
 expected_grace := f.named('expected_grace', united)!
 if compare('ne', f.names['starts'], v(ah.Value(1))!)! || compare('ne', f.names['done'], v(ah.Value(1))!)! { fail('start', [f.names['starts'],f.names['done']], '')! }
 if compared('ne', call('set', o(measurements))!, o(expected))! || compared('ne', call('set', o(live))!, o(expected))! || compared('ne', call('set', o(grace))!, o(expected_grace))! { fail_text('incomplete or unexpected measurement/grace/allocation coverage')! }
 if any_generator('_classes_outside', [o(classes),o(expected)])! { fail_text('class report outside measured cohorts')! }
 if compare('eq', mode, v(ah.Value('waits'))!)! {
  if compared('ne', call('set', o(work))!, o(expected))! { fail_text('missing timed-workload coverage')! }
  if any_generator('_short_work', [o(work)])! { fail_text('300 one-millisecond sleeps consumed less than 300 ms')! }
 } else if truth(work)! { fail_text('unexpected timed-workload report')! }
 if compare('eq', mode, v(ah.Value('directories'))!)! {
  fixed := fresh_dict()!
  put(fixed, v(ah.Value('mkdir_tmpfs'))!, literal(ah.Value(16914836))!)!
  put(fixed, v(ah.Value('mkdir_ext2'))!, literal(ah.Value(61267))!)!
  differs := compare('ne', filesystems, o(fixed))!
  release([fixed])!
  if differs { fail_text('missing or incorrect tmpfs/ext2 identity')! }
 } else if truth(filesystems)! { fail_text('unexpected filesystem report')! }
 if truth(flat_slabinfo)! {
  if compare('ne', mode, v(ah.Value('slabinfo'))!)! { fail_text('flat slabinfo check requires --mode slabinfo')! }
  for cohort in 1 .. 4 {
   id := f.named('cohort', literal(ah.Value(cohort))!)!
   key := tuple_ids([literal(ah.Value('slabinfo'))!,id,literal(ah.Value(48))!])!
   value := method(classes,'get',[o(key),v(ah.Value(0))!],{})!
   release([key])!
   differs := compared('ne',value,v(ah.Value(0))!)!
   if differs { fail('slab',[id],'')! }
  }
  key := tuple_ids([literal(ah.Value('slabinfo'))!,literal(ah.Value(3))!])!
  last := f.named('last',item(measurements,o(key))!)!
  release([key])!
  if any_generator('_unsettled',[o(last)])! { fail_text('last slabinfo cohort has not settled')! }
 }
 if truth(flat_small)! {
  membership := call('_small_mode',o(mode))!
  accepted := tested(membership)!
  if !accepted { fail_text('small-object check requires --mode waits or select')! }
  waits := compare('eq',mode,v(ah.Value('waits'))!)!
  checked := f.named('checked',if waits {tuple_ids([literal(ah.Value('fork_reap'))!])!}else{call('_identity',o(names))!})!
  // The original conditional expression's false branch returns names unchanged.
  marker := f.named('marker',literal(ah.Value(if compare('eq',mode,v(ah.Value('waits'))!)!{'CHURN SEMANTICS: fork executable path preserved'}else{'CHURN SEMANTICS: pselect pointers, masks, timeout, interruption, wake'}))!)!
  checked_it := call('_ITER',o(checked))!
  f.named('_checked_iterator',checked_it)!
  for {
   name_id := next(checked_it)!
   if name_id == '' {break}
   name := f.named('name',name_id)!
   for cohort in 1 .. 4 {
    id := f.named('cohort',literal(ah.Value(cohort))!)!
    maximum := f.named('maximum',literal(ah.Value(if compare('eq',id,v(ah.Value(1))!)!{2}else{0}))!)!
    key := tuple_ids([name,id,literal(ah.Value(16))!])!
    value := method(classes,'get',[o(key),v(ah.Value(0))!],{})!
    release([key])!
    excessive := compared('gt',value,o(maximum))!
    if excessive {fail('small',[name,id],'')!}
   }
  }
  forget(mut f,'_checked_iterator')!
  value := method(source,'count',[o(marker)],{})!
  wrong := compared('ne',value,v(ah.Value(1))!)!
  if wrong {fail_text('missing or duplicate lifetime/ABI semantics evidence')!}
 }
 return tuple_ids([measurements,live])!
}
fn fail_text_id(message string) ! {
 factory := global('ValueError')!
 value := invoke(factory,[o(message)],{})!
 call('_raise',o(value))!
 return error('ValueError callback returned')
}
pub fn dispatch(row map[string]ah.Value) !ah.Value {
 ids := ah.field(row,'arguments').items().map(it.text())
 operation := ah.field(row,'operation').text()
 current_builtins=ids[1]
 order:=if operation=='fields'{['line','result','key','value']}else{['source','mode','flat_slabinfo','flat_small','names','measurements','grace','live','classes','filesystems','starts','done','raw','row','identity','key','count','size','match','expected_grace','cohort','checked','marker','name','maximum','expected','last','line','work']}
 mut f:=Frame{start:checkpoint()!,pins:ids[0],scope:ids[2],order:order}
 for i in 1..ids.len {f.names['argument-'+i.str()]=ids[i]}
 result:=if operation=='fields'{fields(get(f.scope, 'line')!,mut f) or {f.failed(err)!;return err}}else{inspect(ids,mut f) or {f.failed(err)!;return err}}
 f.retire(result)!
 clean_since(f.start,[result])!
 return ah.Value(result)
}
