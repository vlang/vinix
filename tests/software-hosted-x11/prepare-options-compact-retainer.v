// SPDX-License-Identifier: GPL-2.0-or-later
// Derive a fresh compact retainer; never change the original native06 checker.
module main

import crypto.sha256
import json2
import os

const state = '/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02'
const suite = state + '/source/tests/software-hosted-x11'
const output = state + '/compact-retention-setup-01'

fn need(ok bool, message string) ! { if !ok { return error(message) } }

fn change(text string, before string, after string, count int) !string {
	need(text.count(before) == count, 'compact retention transformation count differs: ' + before)!
	result := text.replace(before, after)
	need(result.replace(after, before) == text, 'compact retention transformation is not reversible')!
	return result
}

fn retainer(text string) !string {
	mut result := change(text, 'import launchproof\n', 'import launchproof\nimport compactproof\nimport compactui\n', 1)!
	result = change(result, '\tscenario string\n', '\tscenario string\n\tcompact bool\n', 1)!
	result = change(result, "if digest(os.dir(@FILE) + '/optionsfixture/fixture.v')! != sha256.hexhash(optionsfixture.source()) { return error('literal options fixture source changed after compilation') }",
		"if digest(os.dir(@FILE) + '/optionsfixture/fixture.v')! != sha256.hexhash(optionsfixture.source()) { return error('literal options fixture source changed after compilation') }\n\tif digest(os.dir(@FILE) + '/compactproof/admit.v')! != sha256.hexhash(compactproof.source()) { return error('compact proof source changed after compilation') }\n\tif digest(os.dir(@FILE) + '/compactui/drive.v')! != sha256.hexhash(compactui.source()) { return error('compact UI source changed after compilation') }", 1)!
	result = change(result, "receipt.architecture !in ['aarch64', 'x86_64'] || !receipt.passed",
		"receipt.architecture !in ['aarch64', 'x86_64'] || !receipt.passed || (receipt.compact && !launch_options)", 1)!
	result = change(result, "if launch_options { required_trees << 'clipboard-runtime' }",
		"if launch_options { required_trees << 'clipboard-runtime' }\n\tif receipt.compact { required_trees << ['source:tests/software-hosted-x11/compactproof', 'source:tests/software-hosted-x11/compactui'] }", 1)!
	result = change(result, "proof.copied_sources(work + '/source/tests/software-hosted-x11/optionsfixture', receipt.trees['source:tests/software-hosted-x11/optionsfixture']!.entries)!",
		"proof.copied_sources(work + '/source/tests/software-hosted-x11/optionsfixture', receipt.trees['source:tests/software-hosted-x11/optionsfixture']!.entries)!\n\tif receipt.compact {\n\t\tfor name in ['compactproof', 'compactui'] { proof.copied_sources(work + '/source/tests/software-hosted-x11/' + name, receipt.trees['source:tests/software-hosted-x11/' + name]!.entries)! }\n\t}", 1)!
	result = change(result, "names << ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json']",
		"if receipt.compact {\n\t\tfor frame in compactui.frames() { names << frame.name + '.png' }\n\t\tnames << ['14-compact-painted.png', 'compact-audits-after.json']\n\t\tfor role in ['targets01', 'target-bootstrap01'] {\n\t\t\tfor suffix in ['.log.argv.json', '.log', '.log.exit.json'] { names << 'compact-audits-after/compact-original-' + role + suffix }\n\t\t}\n\t}\n\tnames << ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json']", 1)!
	result = change(result, "// Refuse cheap transcript/phase errors before rehashing entire toolchains",
		"if receipt.compact { compact_bindings(work, receipt)! }\n\t// Refuse cheap transcript/phase errors before rehashing entire toolchains", 1)!
	result = change(result, '\tbuilds(work, receipt)!',
		"\tif receipt.compact { compactui.validate_frames(work)!; painted(work + '/14-compact-painted.png', 2)! }\n\tbuilds(work, receipt)!", 1)!
	result = change(result, "assembled := if launch_options { launchproof.assembled(os.dir(receipt.desktop), os.dir(receipt.trees['stage']!.root), receipt.architecture, compiler)! }",
		"assembled := if receipt.compact { compactproof.recorded_assembled(os.dir(receipt.desktop), os.dir(receipt.trees['stage']!.root), receipt.architecture, compiler, work + '/compact-audits-before.json', receipt.inputs[work + '/compact-audits-before.json']!, work + '/compact-audits-after.json', receipt.outputs['compact-audits-after.json']!)! }\n\t\telse if launch_options { launchproof.assembled(os.dir(receipt.desktop), os.dir(receipt.trees['stage']!.root), receipt.architecture, compiler)! }", 1)!
	result = change(result, "for _, path in assembled {\n\t\tif receipt.inputs[path] or { '' } != digest(path)! { return error('anchored assembled input pin absent') }\n\t}",
		"for role, path in assembled {\n\t\tif receipt.compact && (role == 'compact/audit-record/after' || role.starts_with('compact/post/audit/')) {\n\t\t\tif !path.starts_with(work + '/') || receipt.outputs[path[work.len + 1..]] or { '' } != digest(path)! { return error('compact post-audit output pin absent') }\n\t\t} else if receipt.inputs[path] or { '' } != digest(path)! { return error('anchored assembled input pin absent') }\n\t}", 1)!
	result = change(result, "if launch_options { os.cp(work + '/05-launch-options.png', out + '/05-launch-options.png')! }",
		"if launch_options { os.cp(work + '/05-launch-options.png', out + '/05-launch-options.png')! }\n\tif receipt.compact {\n\t\tfor frame in compactui.frames() { os.cp(work + '/' + frame.name + '.png', out + '/' + frame.name + '.png')! }\n\t\tfor name in ['14-compact-painted.png', 'compact-audits-before.json', 'compact-audits-after.json'] { os.cp(work + '/' + name, out + '/' + name)! }\n\t}", 1)!
	result = change(result, "'scope': if launch_options { 'ordinary installed Software Launch options;",
		"'scope': if receipt.compact { 'ordinary installed Software compact Launch entry and arguments/files/folder/run pages at180x220 and320x240; real resized draft, literal signed operands and explicit file access; current compositor with separate complete original audits; actual compact paint, maximized pointer repaint and close/reap/lease lifecycle; guest shutdown and QEMU exit0' }\n\t\t\telse if launch_options { 'ordinary installed Software Launch options;", 1)!
	return result + retain_support()
}

fn evidence(text string) !string {
	mut result := change(text, 'import optionsfixture\n', 'import optionsfixture\nimport stbi\n', 1)!
	result = change(result, '\tscenario string\n', '\tscenario string\n\tcompact bool\n', 1)!
	result = change(result, '\tmut inputs := map[string]string{}\n',
		"\tif old.compact {\n\t\tfor name in ['compact-audits-before', 'compact-audits-after'] { rebase_compact_record(work + '/' + name + '.json', original, work, name)! }\n\t}\n\tmut inputs := map[string]string{}\n", 1)!
	result = change(result, "receipt := Qualification{old.format, old.scenario, old.architecture,\n\t\tclone_path(old.desktop, original, work, desktop), clone_path(old.desktop_receipt, original, work, desktop), inputs, outputs, trees, old.passed}",
		"receipt := Qualification{...old, desktop: clone_path(old.desktop, original, work, desktop), desktop_receipt: clone_path(old.desktop_receipt, original, work, desktop), inputs: inputs, outputs: outputs, trees: trees}", 1)!
	result = change(result, '\tfor name in cases {\n',
		"\tif receipt.compact { cases << compact_cases() }\n\tfor name in cases {\n", 1)!
	result = change(result, '\t\tmut next := receipt\n\t\tif name.starts_with',
		"\t\tmut next := receipt\n\t\tmut compact_saved := map[string]string{}\n\t\tif name.starts_with('compact-') {\n\t\t\tupdated, expected := compact_mutation(copy, receipt, name, mut compact_saved)!\n\t\t\tnext = updated; reason = expected\n\t\t} else if name.starts_with", 1)!
	result = change(result, "reason = if launch_options { 'hosted launch-options import binding differs' } else { 'assembled input digest differs: desktop/build-inputs.json' }",
		"reason = if receipt.compact { 'compact imported receipt differs' } else if launch_options { 'hosted launch-options import binding differs' } else { 'assembled input digest differs: desktop/build-inputs.json' }", 1)!
	result = change(result, "if name in ['reduced-full-input-tree', 'unselected-source-tree'] { os.write_file(copy + '/inputs-before-build.json', before_snapshot)! }",
		"if name in ['reduced-full-input-tree', 'unselected-source-tree'] || name.starts_with('compact-') { os.write_file(copy + '/inputs-before-build.json', before_snapshot)! }\n\t\tfor relative, value in compact_saved { os.write_file(copy + '/' + relative, value)! }", 1)!
	return result + evidence_support()
}

fn prepare() ! {
	$if prod {} $else { return error('requires production source binding') }
	need(os.args == [os.executable(), '--prepare'], 'requires exact --prepare')!
	need(sha256.hexhash(os.read_file(@FILE)!) == sha256.hexhash($embed_file('prepare-options-compact-retainer.v').to_string()), 'preparer source changed')!
	need(!os.exists(output) && !os.is_link(output), 'compact retention setup output exists')!
	mut originals := map[string]string{}
	for name, hash in {'retain.v': '9a8d5aa7eb271a0818a9fe0c75bf3ace0a00caad3e5fc4d27fcce0732195a3ca',
		'evidence-check.v': 'd2d95972e9ea71c0421769a32a6d277f3baa83e9312dbb4ff91872e8c52dd274'} {
		path := suite + '/' + name
		info := os.lstat(path)!
		need(info.mode & 0o170000 == 0o100000 && info.nlink == 1 && info.size < 128 * 1024, 'requires small independent source')!
		originals[name] = os.read_file(path)!
		need(sha256.hexhash(originals[name]) == hash, 'original compact retention input differs: ' + name)!
	}
	retained := retainer(originals['retain.v'])!
	controls := evidence(originals['evidence-check.v'])!
	os.mkdir(output, mode: 0o700)!
	for name, value in originals { os.write_file(output + '/before-' + name, value)! }
	os.write_file(suite + '/retain.v', retained)!
	os.write_file(suite + '/evidence-check.v', controls)!
	os.write_file(output + '/after-retain.v', retained)!
	os.write_file(output + '/after-evidence-check.v', controls)!
	os.write_file(output + '/result.json', json2.encode({'outcome': 'PREPARED',
		'retain_sha256': sha256.hexhash(retained), 'evidence_sha256': sha256.hexhash(controls),
		'scope': 'Fresh mutable compact retention source only; original checker unchanged; no compile or guest.'}) + '\n')!
	println('PREPARED compact retention branch and supplemental corruption controls; no build or guest')
}

fn retain_support() string {
	return r"

struct CompactAuditRecord {
 format int
 scope string
 source_sha256 string
 paths map[string]string
 hashes map[string]string
}

fn compact_bindings(work string, receipt Qualification) ! {
 for prefix in ['compact-audits-before', 'compact-audits-after'] {
  path := work + '/' + prefix + '.json'
  expected := if prefix.ends_with('before') { receipt.inputs[path] or { '' } }
   else { receipt.outputs[prefix + '.json'] or { '' } }
  if expected.len != 64 { return error('compact ' + prefix + ' record pin missing') }
  if (os.stat(path)!).size > 65536 || digest(path)! != expected { return error('compact ' + prefix + ' record pin differs') }
  record := json2.decode[CompactAuditRecord](os.read_file(path)!, strict: true)!
  for role in ['targets01', 'target-bootstrap01'] {
   for part, suffix in {'argv': '.log.argv.json', 'log': '.log', 'exit': '.log.exit.json'} {
    name := 'audit/' + role + '/' + part
    relative := prefix + '/compact-original-' + role + suffix
    expected_path := work + '/' + relative
    if record.paths[name] or { '' } != expected_path { return error('compact audit callback output path differs') }
    wanted := record.hashes[name] or { '' }
    admitted := if prefix.ends_with('before') { receipt.inputs[expected_path] or { '' } }
     else { receipt.outputs[relative] or { '' } }
    if wanted.len != 64 || admitted != wanted || digest(expected_path)! != wanted { return error('compact audit callback pin differs') }
   }
  }
 }
}
"
}

fn evidence_support() string {
	return r"

struct CompactAuditRecord {
 format int
 scope string
 source_sha256 string
 paths map[string]string
 hashes map[string]string
}

fn rebase_compact_record(path string, original string, copy string, prefix string) ! {
 old := json2.decode[CompactAuditRecord](os.read_file(path)!, strict: true)!
 mut paths := old.paths.clone()
 mut hashes := old.hashes.clone()
 for role, previous in old.paths {
  if !role.starts_with('audit/') { continue }
  if !previous.starts_with(original + '/' + prefix + '/') { return error('compact original callback escaped run-owned namespace') }
  paths[role] = move_path(previous, original, copy)
  hashes[role] = proof.digest(paths[role])!
 }
 os.write_file(path, json2.encode(CompactAuditRecord{...old, paths: paths, hashes: hashes}) + '\n')!
}

fn compact_cases() []string {
 return ['compact-missing-320-frame', 'compact-missing-180-frame', 'compact-wrong-180-geometry',
  'compact-broken-top-margin', 'compact-paint-phase', 'compact-missing-before-record-pin',
  'compact-missing-after-record-pin', 'compact-before-record-pin-mismatch', 'compact-after-record-pin-mismatch',
  'compact-stripped-flag', 'compact-missing-proof-tree', 'compact-missing-ui-tree',
  'compact-copied-proof-source', 'compact-copied-ui-source', 'compact-after-record-header',
  'compact-after-record-marker', 'compact-after-record-exit', 'compact-after-record-argv',
  'compact-before-complete-path', 'compact-reused-audit-phase']
}

fn compact_save(work string, relative string, mut saved map[string]string) ! {
 if relative !in saved { saved[relative] = os.read_file(work + '/' + relative)! }
}

fn compact_input(work string, receipt Qualification, relative string, hash string) !Qualification {
 path := work + '/' + relative
 mut inputs := receipt.inputs.clone()
 mut before := json2.decode[map[string]string](os.read_file(work + '/inputs-before-build.json')!)!
 if hash == '' { inputs.delete(path); before.delete(path) } else { inputs[path] = hash; before[path] = hash }
 os.write_file(work + '/inputs-before-build.json', json2.encode(before))!
 for name in ['inputs.json', 'inputs-verified.json'] { os.write_file(work + '/' + name, json2.encode(inputs))! }
 mut outputs := receipt.outputs.clone()
 for name in ['inputs-before-build.json', 'inputs.json', 'inputs-verified.json'] { outputs[name] = proof.digest(work + '/' + name)! }
 next := Qualification{...receipt, inputs: inputs, outputs: outputs}
 save(work, next)!
 return next
}

fn compact_output(work string, receipt Qualification, relative string) !Qualification {
 mut outputs := receipt.outputs.clone()
 outputs[relative] = proof.digest(work + '/' + relative)!
 next := Qualification{...receipt, outputs: outputs}
 save(work, next)!
 return next
}

fn compact_mutation(work string, receipt Qualification, name string, mut saved map[string]string) !(Qualification, string) {
 mut next := receipt
 if name in ['compact-missing-320-frame', 'compact-missing-180-frame', 'compact-missing-after-record-pin'] {
  relative := if name == 'compact-missing-320-frame' { '06-compact-catalog-320.png' }
   else if name == 'compact-missing-180-frame' { '07-compact-catalog-180.png' } else { 'compact-audits-after.json' }
  mut outputs := receipt.outputs.clone(); outputs.delete(relative)
  next = Qualification{...receipt, outputs: outputs}; save(work, next)!
  return next, 'output pin differs: ' + relative
 }
 if name in ['compact-wrong-180-geometry', 'compact-broken-top-margin', 'compact-paint-phase'] {
  relative := if name == 'compact-wrong-180-geometry' { '07-compact-catalog-180.png' }
   else if name == 'compact-broken-top-margin' { '06-compact-catalog-320.png' } else { '14-compact-painted.png' }
  compact_save(work, relative, mut saved)!
  if name == 'compact-wrong-180-geometry' { os.cp(work + '/06-compact-catalog-320.png', work + '/' + relative)! }
  else if name == 'compact-paint-phase' { os.cp(work + '/03-pointer.png', work + '/' + relative)! }
  else {
   mut image := stbi.load(work + '/' + relative, stbi.LoadParams{desired_channels: 3})!
   defer { image.free() }
   if image.width != 1024 || image.height != 768 { return error('compact baseline image size differs') }
   unsafe { image.data[(70 * 1024 + 120) * 3] = 0 }
   stbi.stbi_write_png(work + '/' + relative, image.width, image.height, 3, image.data, image.width * 3)!
  }
  next = compact_output(work, receipt, relative)!
  return next, if name == 'compact-wrong-180-geometry' { 'compact body horizontal extent differs' }
   else if name == 'compact-broken-top-margin' { 'compact body top margin differs' } else { 'painted X11 framebuffer phase differs' }
 }
 if name == 'compact-missing-before-record-pin' {
  return compact_input(work, receipt, 'compact-audits-before.json', '')!, 'compact compact-audits-before record pin missing'
 }
 if name in ['compact-before-record-pin-mismatch', 'compact-after-record-pin-mismatch'] {
  if name == 'compact-before-record-pin-mismatch' { return compact_input(work, receipt, 'compact-audits-before.json', '0'.repeat(64))!, 'compact compact-audits-before record pin differs' }
  mut outputs := receipt.outputs.clone(); outputs['compact-audits-after.json'] = '0'.repeat(64)
  next = Qualification{...receipt, outputs: outputs}; save(work, next)!
  return next, 'compact compact-audits-after record pin differs'
 }
 if name == 'compact-stripped-flag' { next = Qualification{...receipt, compact: false}; save(work, next)!; return next, 'unexpected native output' }
 if name in ['compact-missing-proof-tree', 'compact-missing-ui-tree'] {
  mut trees := receipt.trees.clone()
  trees.delete('source:tests/software-hosted-x11/' + if name == 'compact-missing-proof-tree' { 'compactproof' } else { 'compactui' })
  next = Qualification{...receipt, trees: trees}; save(work, next)!
  return next, 'required complete input tree missing'
 }
 if name in ['compact-copied-proof-source', 'compact-copied-ui-source'] {
  relative := 'source/tests/software-hosted-x11/' + if name == 'compact-copied-proof-source' { 'compactproof/admit.v' } else { 'compactui/drive.v' }
  compact_save(work, relative, mut saved)!
  os.write_file(work + '/' + relative, saved[relative] + '\n')!
  return compact_input(work, receipt, relative, proof.digest(work + '/' + relative)!)!, 'frozen source inventory differs'
 }
 prefix := if name == 'compact-before-complete-path' { 'compact-audits-before' } else { 'compact-audits-after' }
 relative := prefix + '.json'
 compact_save(work, relative, mut saved)!
 old := json2.decode[CompactAuditRecord](saved[relative], strict: true)!
 mut changed := old
 mut reason := ''
 if name == 'compact-after-record-header' { changed = CompactAuditRecord{...old, format: 2}; reason = 'recorded compact audit header differs' }
 else if name == 'compact-before-complete-path' {
  mut paths := old.paths.clone(); paths['complete/targets01'] = paths['complete/target-bootstrap01']
  changed = CompactAuditRecord{...old, paths: paths}; reason = 'recorded original complete input path differs'
 } else if name == 'compact-reused-audit-phase' {
  changed = json2.decode[CompactAuditRecord](os.read_file(work + '/compact-audits-before.json')!, strict: true)!
  reason = 'compact audit callback output path differs'
 } else if name in ['compact-after-record-marker', 'compact-after-record-exit', 'compact-after-record-argv'] {
  part := if name == 'compact-after-record-marker' { 'log' } else if name == 'compact-after-record-exit' { 'exit' } else { 'argv' }
  role := 'audit/targets01/' + part
  path := old.paths[role]
  if !path.starts_with(work + '/' + prefix + '/') { return error('compact private audit callback path escaped') }
  callback_relative := path[work.len + 1..]
  compact_save(work, callback_relative, mut saved)!
  if part == 'log' { os.write_file(path, saved[callback_relative] + saved[callback_relative])!; reason = 'original compact complete audit marker differs' }
  else if part == 'exit' { os.write_file(path, json2.encode({'exit_code': 1}))!; reason = 'original compact complete audit actual-exit receipt differs' }
  else {
   mut argv := json2.decode[[]string](saved[callback_relative])!; argv[1] = 'seal'
   os.write_file(path, json2.encode(argv))!; reason = 'original compact complete audit argv differs'
  }
  mut hashes := old.hashes.clone(); hashes[role] = proof.digest(path)!
  changed = CompactAuditRecord{...old, hashes: hashes}
  next = compact_output(work, next, callback_relative)!
 } else { return error('unknown compact control: ' + name) }
 os.write_file(work + '/' + relative, json2.encode(changed) + '\n')!
 if prefix.ends_with('before') { next = compact_input(work, next, relative, proof.digest(work + '/' + relative)!)! }
 else { next = compact_output(work, next, relative)! }
 return next, reason
}
"
}

fn main() { prepare() or { eprintln(err); exit(1) } }
