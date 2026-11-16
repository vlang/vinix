module g13contract

import g13layout

fn test_render_retirement_keeps_independent_stages_and_shared_failure_gate() {
 native := read(g13layout.repo_root() + '/kernel/gpu/agx/gpu/g13.v')!
 check_render_retirement_local(native)!
 for token in ['if vertex_done && !job.vertex_retirement_published',
  'if fragment_done && !job.fragment_retirement_published',
  'if job.retirement_failed && !job.quarantined',
  'return if fragment_done { -1 } else { 0 }', 'return if vertex_done { -1 } else { 0 }',
  'if retirement == 0 { continue }', 'job.retirement_published = true'] {
  if _ := check_render_retirement_local(native.replace(token, '')) { assert false, token }
 }
}
