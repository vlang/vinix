import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	os.write_file(area + '/q2-ready-initial.log', 'Initial readiness helper exited1 before checking artifacts or changing common provenance logs: expected generated-review-x86-track.log.status, but the generated-C review helper writes generated-review-x86-track.status. Corrected the readiness helper to read the actual status filename and write refreshed common provenance statuses consistently. All four build and C-review commands had already exited0. This is a host evidence-helper failure, not a guest result.\n')!
	os.write_file(area + '/q2-ready-initial.log.status', '1\n')!
}
