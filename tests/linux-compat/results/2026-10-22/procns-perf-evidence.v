import os
import json2
import crypto.sha256

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
 if os.args.len == 2 && os.args[1] == 'review' {
  os.write_file(area + '/evidence-review.md', '# Independent evidence checker review\n\nReviewer: /root/lifetime_review (read-only). Checked procns-check.v and the private publisher on 2026-10-22.\n\nThe checker requires all published digests and current source digests to match. It checks both architectures; candidate cohorts must have equal before/after counts for every reported size class, zero operation errors, flat big-page counts and no write-after-free counts. Baseline child and concurrent-child cohorts must grow. Four reader workers must each report positive call counts. Both kernels use identical fixture hashes. The unchanged Linux reference must pass using that same fixture hash. The held O_PATH, cwd, parent and inherited cwd marker is mandatory. Six adjacent compatibility fixtures and tracking/production build statuses are required on each architecture. Two subprocess negative controls ensure assertions execute and candidate flat measurements cannot pass as the growing baseline.\n\nThe publisher preserves initial failed attempts separately, publishes raw logs and structured receipts, pins source files and retains larger inputs by absolute path and hash. Content-addressed immutable publish destinations refuse replacement by different bytes. Published manifests are evidence records rather than a cryptographic trust boundary: a coordinated rewrite of logs, receipts and their manifest remains outside this checker. Exact baseline commit equality and receipt-level regression serial hashes were suggested to the author as useful provenance tightening; the checked initial publisher already included all regression logs in its digested files map.\n\nReview limits: source review, not an independent rebuild or a proof of every possible malformed log. The checker uses the trusted producer\'s schema and fixed date directory. Numerical token canonicalization and mandatory membership of every known path in the manifest are not separately enforced. Existing data and source are additionally retained and can be audited directly.\n')!
  mut pins := []string{}
  for path in ['/Users/alex/code/vinix/tests/linux-compat/procns-check.v', area + '/publish.v'] {
   pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path
  }
  os.write_file(area + '/evidence-review-inputs.sha256', pins.join('\n') + '\n')!
  mut review := os.read_file(area + '/evidence-review.md')!
  review += '\nThe follow-up checker now binds each baseline kernel hash to baseline-inputs.json, its historical worktree commit, successful build status, build log/status hashes, clean audit-base tracked state, base record and build controller hash. This preserves the original receipt\'s honest unavailable-git field while checking the historical commit provenance separately. No additional refusal blocker found in that change.\n'
  os.write_file(area + '/evidence-review.md', review)!
  return
 }
 if os.args.len == 2 && os.args[1] == 'notes' {
  mut notes := os.read_file(area + '/perf-qualification-notes.md')!
  notes += '\nThe first smaller-image desktop attempt is an invalid harness run: the cached image lacks od and install. The guest therefore failed to register its user and copy the selected desktop, and readiness timed out after 120 seconds. Preserve perf-small-desktop-producer.log, perf-small-desktop/serial.log, perf-small-desktop.json ([]), and perf-small-desktop.status (1). No kernel qualification is claimed from it.\n\nThe desktop retry uses frozen-perf-compat. A V helper copied the initial frozen harness, substituted the literal hexadecimal encoding of the known Perf User name for od, and replaced install with cp plus chmod. These changes affect private test setup only. Sources, both frozen module copies, fixture inputs, driver binaries, compiler and selected image/kernel/desktop are pinned in the perf-*inputs.sha256 manifests.\n\nThe retry completed idle, apps and drag on the exact cf642 ARM tracking kernel with the selected cached desktop. All three scenarios reached readiness in one second and measured five seconds. Idle: four processes, 0.38% total CPU, 80.8 MB process memory, 127.0 MB physical memory. Apps: nine processes, 0.92%, 177.8 MB, 245.5 MB. Drag: nine processes, 2.18%, 177.9 MB, 235.7 MB. The numeric and process-tree checks passed; screenshots were not requested, and no visual screenshot comparison is claimed. This is a one-round functional performance qualification using cached desktop and short measurements, not a statistically controlled performance comparison.\n'
  os.write_file(area + '/perf-qualification-notes.md', notes)!
  return
 }
 if os.args.len == 2 && os.args[1] == 'final-notes' {
  mut notes := os.read_file(area + '/perf-qualification-notes.md')!
  notes += '\nThe ops/churn/cache guest completed with status 0 and exactly one DONE marker. All 36 distinct operation/directory combinations ran 200 measured iterations after matching warmup and 13-second grace waits; every bytes_per_op value was zero and there were no per-class deltas. All four expected programs ran 300 measured churn iterations after matching warmup: retained_kb=0 and per_run_bytes=0 for each, with no PERF-SLAB delta rows. The cache scenario wrote 32 MiB and retained 20 MiB overall; Cached was 16,384 KiB and Slab 37,168 KiB. Adjacent PERF-MEMINFO agreed on Cached; Slab was 37,200 KiB (32 KiB higher while separate shell probes ran). The cache bounds were declared before the result: used_mb 0..64, cached_kb 0..65,536, nonnegative slab with at most 1 MiB skew between probes.\n\nverify-perf-results.v independently audits raw serial output rather than relying on wrapper status. It verifies expected operations/programs, unique scenarios and process IDs, zero retention/deltas, numeric cache bounds, five-second desktop results, required native app processes, drag drive marker, raw/JSON equality, no PERF-ERROR/panic and one START/DONE pair per valid guest. It also requires two subprocess negative controls to reject (disabled assertions and a desktop log substituted for the ops log). perf-results-audit.log/status record PASS/0.\n\nThe original generic SHA helper copied and pinned the frozen modules in memory before guest launch but remained busy hashing the unused 6.68 GB default image. resume-perf-pins.v completed the equivalent sorted manifest later from those frozen copies using the host CommonCrypto SHA-256 primitive, with complete byte-count checks; the unused image hash is retained for the failed preparation, and excluded from post-run used-input checks. Selected image, kernel, desktop and final driver binaries had separate small/compat manifests before their valid guest launches. The frozen used-input manifest additionally includes both copied module/header sets and host dependencies. All used input manifests are checked again after the guest runs.\n'
  os.write_file(area + '/perf-qualification-notes.md', notes)!
  return
 }
 mut files := map[string]string{}
 names := ['perf-qualification-notes.md', 'perf-ops-producer.log', 'perf-ops.error', 'perf-ops.status', 'perf-small-desktop-producer.log', 'perf-small-desktop.json', 'perf-small-desktop.status', 'perf-compat-desktop-producer.log', 'perf-compat-desktop.json', 'perf-compat-desktop.status', 'perf-small-ops-producer.log', 'perf-small-ops.json', 'perf-small-ops.status', 'perf-inputs.sha256', 'perf-small-inputs.sha256', 'perf-compat-inputs.sha256', 'perf-frozen-used-inputs.sha256', 'perf-post-inputs-check.log', 'perf-post-inputs-check.status', 'perf-frozen-compile.log', 'perf-compat-compile.log', 'freeze-perf.log', 'pin-perf-small.log', 'lifetime-review.md', 'generated-review-inputs.sha256', 'generated-review-arm-excerpts.c', 'generated-review-x86-excerpts.c', 'generated-review-comparison.log', 'evidence-review.md', 'generated-review.v', 'freeze-perf.v', 'retry-perf.v', 'pin-perf-small.v', 'prepare-perf-compat.v', 'pin-perf-used.v', 'verify-perf.v', 'perf-evidence.v', 'desktop-retention.v']
 for name in names {
  path := area + '/' + name
  assert os.is_file(path), path
  files[name] = path
 }
 files['evidence-review-inputs.sha256'] = area + '/evidence-review-inputs.sha256'
 files['pin-perf-used.log'] = area + '/pin-perf-used.log'
 files['resume-perf-pins.v'] = area + '/resume-perf-pins.v'
 files['resume-perf-pins.log'] = area + '/resume-perf-pins.log'
 files['resume-perf-pins-commoncrypto.log'] = area + '/resume-perf-pins-commoncrypto.log'
 for name in ['verify-perf-results.v', 'run-perf-audits.v', 'perf-results-audit.log', 'perf-results-audit.status', 'perf-post-inputs-audit.log', 'perf-post-inputs-audit.status'] { files[name] = area + '/' + name }
 for group in ['perf-small-desktop', 'perf-compat-desktop', 'perf-small-ops'] {
  path := area + '/' + group + '/serial.log'
  assert os.is_file(path), path
  files[group + '-serial.log'] = path
 }
 for group in ['frozen-perf', 'frozen-perf-compat', 'frozen-perf-drag'] {
  mut paths := os.walk_ext(area + '/' + group, '.v')
  paths << os.walk_ext(area + '/' + group, '.h')
  paths << area + '/' + group + '/measure.c'
  paths << area + '/' + group + '/perf-init.sh'
  for path in paths {
   name := 'perf-' + path.all_after(area + '/').replace('/', '-')
   assert name !in files
   files[name] = path
  }
 }
 for name in ['prepare-perf-drag.v', 'verify-perf-drag.v', 'perf-drag-inputs.sha256', 'perf-drag-compile.log', 'perf-drag-desktop-producer.log', 'perf-drag-desktop.json', 'perf-drag-desktop.status', 'perf-drag-audit.log', 'perf-drag-audit.status', 'perf-drag-shots.sha256'] { files[name] = area + '/' + name }
 files['perf-drag-desktop-serial.log'] = area + '/perf-drag-desktop/serial.log'
 for name in ['before-drag.ppm', 'new-drag-1.ppm', 'before-drag.png', 'new-drag-1.png'] { files['perf-drag-' + name] = area + '/perf-drag-shots/' + name }
 for _, path in files { assert os.is_file(path), path }
 os.write_file(area + '/perf-publication-inputs.json', json2.encode(files, prettify: true) + '\n')!
 println('Perf publication sources: ' + files.len.str())
}
