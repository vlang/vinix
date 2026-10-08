// SPDX-License-Identifier: GPL-2.0-or-later
module agxhost

const vm_renderer_marker = 'GL_RENDERER=Vinix Fake G17C (M5 Max ABI)'
const vm_completion_marker = 'render submit and fence completed successfully; pixels unchecked'
const vm_fault_rejection_marker = 'vinix-agx-fault: invalid Mesa resource submission rejected'
const vm_guest_command = 'rc=0; for mode in --depth --stencil --depth-stencil; do /usr/bin/run-gl-triangle-agx --submit-only "$mode" || { rc=$?; break; }; done; if [ "$rc" -eq 0 ]; then for fault in overlap rebind lifetime; do env VINIX_AGX_FAULT="$fault" /usr/bin/run-gl-triangle-agx --submit-only --depth-stencil || { rc=$?; break; }; done; fi; if [ "$rc" -eq 0 ]; then for fault in unbind readonly; do if env VINIX_AGX_FAULT="$fault" /usr/bin/run-gl-triangle-agx --submit-only --depth-stencil; then rc=1; break; fi; done; fi; if [ "$rc" -eq 0 ]; then printf \'VINIX_FAKE_G17_VM_%s\\n\' PASS; else printf \'VINIX_FAKE_G17_VM_FAIL:%s\\n\' "$rc"; fi\n'
const vm_attachment_markers = [
	'attachment mode=depth depth=16 stencil=0'
	'attachment mode=stencil depth=0 stencil=8'
	'attachment mode=depth-stencil depth=24 stencil=8'
]
const vm_fault_markers = [
	'vinix-agx-fault: overlapping Mesa binding rejected'
	'vinix-agx-fault: Mesa binding unbound and reused'
	'vinix-agx-fault: referenced depth metadata unbound'
	'vinix-agx-fault: referenced depth metadata made read-only'
	'vinix-agx-fault: referenced GEM handle closed while job pending'
	'vinix-agx-fault: GPU VA reuse blocked while job pending'
	'vinix-agx-fault: in-flight unbind rejected'
	'vinix-agx-fault: in-flight queue destroy rejected'
	'vinix-agx-fault: GPU VA reused after retirement'
]
const vm_expected_resources = ['1/1/0/0', '0/0/1/1', '1/1/1/1', '1/1/1/1', '1/1/1/1', '1/1/1/1']

pub fn vm_line_marker(text string, fail bool) bool {
	marker := if fail { 'VINIX_FAKE_G17_VM_FAIL:' } else { 'VINIX_FAKE_G17_VM_PASS' }
	mut start := 0
	for start <= text.len - marker.len {
		position := text[start..].index(marker) or { return false }
		at := start + position
		start = at + marker.len
		if at != 0 && text[at - 1] != `\n` { continue }
		mut end := start
		if fail {
			for end < text.len && text[end].is_digit() { end++ }
			if end == start { continue }
		}
		for end < text.len && text[end] == `\r` { end++ }
		if end == text.len || text[end] == `\n` { return true }
	}
	return false
}

pub fn vm_shell_prompt(text string) bool {
	if text.contains('\x1b[?2004h') { return true }
	mut end := text.len
	// Python's $ also matches immediately before a final newline.
	if end > 0 && text[end - 1] == `\n` { end-- }
	if end < 2 || text[end - 2..end] != '# ' { return false }
	mut begin := end - 2
	for begin > 0 && text[begin - 1] !in [`\r`, `\n`] { begin-- }
	return end - begin <= 98 && (begin == 0 || text[begin - 1] == `\n`)
}

pub fn vm_resource_states(text string) []string {
	prefix := 'fake-g17: first Mesa render verified;'
	mut result := []string{}
	mut cursor := 0
	for cursor < text.len {
		found := text[cursor..].index(prefix) or { break }
		begin := cursor + found + prefix.len
		mut line_end := begin
		for line_end < text.len && text[line_end] !in [`\r`, `\n`] { line_end++ }
		mut last := -1
		mut finish := 0
		mut state := ''
		mut at := begin
		for at < line_end {
			found_depth := text[at..line_end].index(' depth=') or { break }
			candidate := at + found_depth
			mut pos := candidate
			mut fields := []string{}
			for label in [' depth=', ' depth-meta=', ' stencil=', ' stencil-meta='] {
				if pos + label.len >= line_end || text[pos..pos + label.len] != label || text[pos + label.len] !in [`0`, `1`] { break }
				fields << text[pos + label.len..pos + label.len + 1]
				pos += label.len + 1
			}
			if fields.len == 4 { last = candidate; finish = pos; state = fields.join('/') }
			at = candidate + 1
		}
		if last >= 0 { result << state; cursor = finish } else { cursor = begin }
	}
	return result
}

pub fn vm_child_exit_code(status int) int {
	if C.WIFEXITED(status) != 0 { return C.WEXITSTATUS(status) }
	if C.WIFSIGNALED(status) != 0 { return 128 + C.WTERMSIG(status) }
	return 1
}

pub fn vm_missing(output string, command_sent bool, pass_seen bool, fail_seen bool, forced_stop bool, status int, has_status bool) []string {
	mut missing := []string{}
	if !command_sent { missing << 'guest shell prompt' }
	if output.count(vm_renderer_marker) != 8 { missing << 'Mesa G17 renderer for all eight cases' }
	for index, marker in vm_attachment_markers {
		count := [1, 1, 6][index]
		if output.count(marker) != count { missing << marker + ' exactly ' + count.str() + ' time(s)' }
	}
	if output.count(vm_completion_marker) != 6 { missing << 'render/fence completion for six valid cases' }
	states := vm_resource_states(output)
	if states != vm_expected_resources {
		observed := if states.len == 0 { 'none' } else { "['" + states.join("', '") + "']" }
		missing << 'depth/stencil descriptor resources (observed ' + observed + ')'
	}
	for marker in vm_fault_markers { if output.count(marker) != 1 { missing << marker } }
	if output.count(vm_fault_rejection_marker) != 2 { missing << 'both invalid Mesa resource submissions rejected' }
	if !pass_seen { missing << 'guest PASS marker' }
	if fail_seen { missing << 'guest command returned failure' }
	if forced_stop { missing << 'VM did not exit after the test' }
	if has_status && vm_child_exit_code(status) != 0 { missing << 'VM exit status ' + vm_child_exit_code(status).str() }
	return missing
}
