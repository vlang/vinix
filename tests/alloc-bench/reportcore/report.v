// SPDX-License-Identifier: BSD-2-Clause
module reportcore

import comparecore as b
import evidencearchive as archive
import json2
import os
import time

fn C.snprintf(&char, usize, &char, ...) i32

pub const source_sha = 'bd4a0d74f4f1e8d079d55877f8e90925e2622ce990120b54573a5dc94a9a54b9'
pub const legacy_compare_sha = 'e12ec5a8c90cab335c40e68257d596e0a2d0ba9f284b1e4bfe911fffa352dd06'
pub const core_sha = '287b82b6961b0db3684d83f75e9ef9dbbc24e2daf908f6551ecbe5d1b52d1b58'
pub const cli_sha = '339c36991bc7d3e60af819599e5ba96eb6bc0d4f1a55d4a97818057b45baf18a'
pub const order = ['vinix-1', 'catalina-1', 'catalina-2', 'vinix-2']
pub const provenance_fields = ['kernel_sha256', 'source_sha256', 'libc_sha256', 'libc_a_sha256',
	'libc_build']
pub const method = 'All recorded raw samples participate, including outliers; no filtering or selection.'

pub struct Profile {
pub:
	campaign    string
	version     string
	kernel      string
	loader      string
	static_hash string
	patch       string
	plan        string
}

pub fn profile(campaign string) !Profile {
	return match campaign {
		'2026-10-02-userspace' {
			Profile{campaign, 'v4', 'f944412c7e30b2c3a25b2ef93938bdd21c311c6fa611ea08a76d45adfdd76733', '21258229461f6415812edc34ae2fb83525b9caeba863287a7bc37acac60baef4', '0f6227b80a608e4f487c554f1ed263f911223e0acf2e5be5ee1e67671fc5cd7c', 'ff14e55c5346e6add14c5bb085fcecb957c756b262231e21ee981a4b536d133e', ''}
		}
		'2026-10-03-userspace-v5' {
			Profile{campaign, 'v5', '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74', '6cf9e5ead03671c57dc0661e0fc02a675a34a5cf57826a09452001ded8932b03', 'eb50810aa7d3583f6469e23fce4c2f464a86197cfb2a0cdf5293b75baaedd90c', '5ff7f0e2fdc9525d83b43fa98fdc27e34d5ef2e6d7f7b74e29c57113a34eca86', ''}
		}
		'2026-10-03-userspace-v6' {
			Profile{campaign, 'v6', '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74', 'ad78977e92f55d85ace71f1ca43bf650d216923ed3cf6650dd29f22c1d70af9d', '8d5c3deee3610c07c3f9bbfaee3b4fed244ef35051c3e2390e4452b13db34ace', 'ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d', 'df9db0e94ba5b9bce3ac71fbdfed469642b5b0a6492c764a44fd69df5e9ba012'}
		}
		else { return error('Unknown saved campaign: ' + campaign) }
	}
}

pub fn num(value i64) b.Value { return b.Number{value.str()} }

pub fn strings(values []string) b.Value { return b.Value(values.map(b.Value(it))) }

pub fn qemu() b.Config {
	return {
		'qemu_version': b.Value('QEMU emulator version 11.1.1')
		'machine':      b.Value('q35,vmport=off')
		'accelerator':  b.Value('tcg,thread=single,tb-size=1024')
		'cpu':          b.Value('Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt')
		'smp':          b.Value('2,sockets=1,cores=2,threads=1')
		'memory_mb':    num(4096)
	}
}

pub fn object(path string) !b.Config {
	raw := json2.decode[b.Value](os.read_file(path)!)!
	if raw is map[string]b.Value { return raw }
	return error(os.file_name(path) + ': JSON object required')
}

fn obj(value b.Value, context string) !b.Config {
	if value is map[string]b.Value { return value }
	return error(context)
}

pub struct Context {
pub:
	root              string
	here              string
	validator         string
	preserved_compare string
	profile           Profile
}

pub fn context(root string, here string, campaign string) !Context {
	mut reader := archive.reader(root)!
	defer { reader.close() }
	original := reader.read(archive.source_commit + ':tests/alloc-bench/results/' + campaign + '/compare.py')!
	if archive.digest(original.content) != legacy_compare_sha {
		return error('Historical strict validator hash differs')
	}
	return Context{root, here, root + '/tests/alloc-bench', original.content, profile(campaign)!}
}

pub fn (ctx Context) preserved_source(name string) !string {
	if name == 'compare.py' { return ctx.preserved_compare }
	path := ctx.here + '/' + name
	if os.exists(path) || name != 'bench.c' { return os.read_file(path) }
	return archive.read_source(ctx.root, 'tests/alloc-bench/results/' + ctx.profile.campaign + '/' + name)
}

fn (ctx Context) validator() ! {
	records := object(ctx.here + '/source-snapshots.json')!
	record := obj(b.value(records, 'compare.py'), 'preserved compare.py differs from source-snapshots.json')!
	if !b.equal(b.value(record, 'sha256'), b.Value(legacy_compare_sha)) || archive.digest(ctx.preserved_compare) != legacy_compare_sha {
		return error('preserved compare.py differs from source-snapshots.json')
	}
	for name, expected in {
		'comparecore/core.v': core_sha
		'compare.v':          cli_sha
	} {
		if archive.digest(os.read_file(ctx.validator + '/' + name)!) != expected {
			return error('native strict validator differs: ' + name)
		}
	}
}

fn numbered(here string, prefix string) ![]int {
	mut result := []int{}
	for name in os.ls(here)! {
		if !name.starts_with(prefix + '-') || !os.is_dir(here + '/' + name) { continue }
		digits := name[prefix.len + 1..]
		if digits == '' || digits[0] == `0` || !digits.bytes().all(it.is_digit()) { continue }
		// Only the two declared cohorts can be accepted; do not overflow an int
		// while recognizing an arbitrarily long, undeclared positive directory.
		result << if digits == '1' {
			1
		} else if digits == '2' {
			2
		} else {
			3
		}
	}
	result.sort()
	return result
}

fn require_same(runs []b.Run, field string) ! {
	expected := b.value(runs[0].config, field)
	if expected is json2.Null { return error('${runs[0].name}: missing config ${field}') }
	for run in runs[1..] {
		if !b.equal(b.value(run.config, field), expected) {
			return error('final cohorts differ in ${field}: ${runs[0].name}, ${run.name}')
		}
	}
}

fn string_list(value b.Value) ![]string {
	if value is []b.Value {
		if value.len == 0 { return error('complete argv required') }
		mut result := []string{}
		for item in value {
			if item is string { result << item } else { return error('complete argv required') }
		}
		return result
	}
	return error('complete argv required')
}

fn validate_manifest(run b.Run) ! {
	for field in ['iterations', 'samples'] {
		if !b.equal(b.value(run.config, field), num(run.meta[field].i64())) {
			return error('${run.name}: config ${field} disagrees with benchmark metadata')
		}
	}
	if run.meta['iterations'] != '200000' || run.meta['samples'] != '7' {
		return error('${run.name}: final captures require 200000 iterations and seven samples')
	}
	for field, value in qemu() {
		if !b.equal(b.value(run.config, field), value) {
			return error('${run.name}: config ${field} differs from declared campaign')
		}
	}
	argv := string_list(b.value(run.config, 'argv')) or { return error('${run.name}: complete QEMU argv required') }
	for option, field in {
		'-machine': 'machine'
		'-accel':   'accelerator'
		'-cpu':     'cpu'
		'-smp':     'smp'
		'-m':       'memory_mb'
	} {
		mut positions := []int{}
		for index, arg in argv { if arg == option { positions << index } }
		value := b.value(run.config, field)
		text := if value is string { value } else { b.repr(value) }
		if positions.len != 1 || positions[0] + 1 >= argv.len || argv[positions[0] + 1] != text {
			return error('${run.name}: actual QEMU ${option} disagrees with config ${field}')
		}
	}
}

// Parse the explicit UTC forms emitted by Python's ISO formatter and standard
// ISO basic/extended times. Fractions truncate to microseconds, as the original
// datetime parser does; calendar validation rejects rollover and leap seconds.
pub fn utc_time(value b.Value, context string) !time.Time {
	if value !is string { return error(context + ': UTC timestamp required') }
	text := value as string
	if text.len < 9 || text.contains('\x00') { return error(context + ': invalid timestamp') }
	mut date_len := if text[4] == `-` { 10 } else { 8 }
	mut week_date := false
	if text[4..].starts_with('-W') {
		week_date = true
		date_len = if text.len > 8 && text[8] == `-` { 10 } else { 8 }
	} else if text[4] == `W` {
		week_date = true
		date_len = if text[7].is_digit() { 8 } else { 7 }
	}
	if text.len <= date_len { return error(context + ': invalid timestamp') }
	mut date := text[..date_len].replace('-', '')
	if week_date {
		if date.len !in [7, 8] || date[4] != `W` || !date[..4].bytes().all(it.is_digit()) || !date[5..].bytes().all(it.is_digit()) {
			return error(context + ': invalid timestamp')
		}
		year := date[..4].int()
		week := date[5..7].int()
		day := if date.len == 8 { date[7..].int() } else { 1 }
		if year < 1 || week < 1 || week > 53 || day < 1 || day > 7 {
			return error(context + ': invalid timestamp')
		}
		january4 := time.parse_iso8601('${year:04}-01-04T00:00:00Z')!
		calendar := january4.add_seconds((7 * (week - 1) + day - january4.day_of_week()) * 86400)
		thursday := calendar.add_seconds((4 - calendar.day_of_week()) * 86400)
		if thursday.year != year || calendar.year < 1 || calendar.year > 9999 {
			return error(context + ': invalid timestamp')
		}
		date = '${calendar.year:04}${calendar.month:02}${calendar.day:02}'
	} else if date.len != 8 || !date.bytes().all(it.is_digit()) || (date_len == 10 && (text[4] != `-` || text[7] != `-`)) {
		return error(context + ': invalid timestamp')
	}
	remaining := text[date_len..].runes()
	mut clock := remaining[1..].string()
	mut zone := ''
	if clock.ends_with('Z') {
		zone = 'Z'
		clock = clock[..clock.len - 1]
	} else {
		mut position := -1
		for index := 0; index < clock.len; index++ {
			if clock[index] in [`+`, `-`] {
				position = index
				break
			}
		}
		if position >= 0 {
			zone = clock[position..]
			clock = clock[..position]
		}
	}
	if zone == '' { return error(context + ': timestamp must explicitly use UTC') }
	if zone != 'Z' {
		zone_time := zone[1..].replace(',', '.')
		if zone_time.all_before('.').contains(':') && zone_time.all_before('.').split(':').any(it.len != 2) {
			return error(context + ': invalid timestamp')
		}
		offset := zone_time.replace(':', '')
		integral := offset.all_before('.')
		if integral.len !in [2, 4, 6] || !integral.bytes().all(it.is_digit()) || (offset.contains('.') && (offset.all_after('.') == '' || !offset.all_after('.').bytes().all(it.is_digit()))) {
			return error(context + ': invalid timestamp')
		}
		if integral.bytes().any(it != `0`) || (offset.contains('.') && offset.all_after('.').bytes().any(it != `0`)) {
			return error(context + ': timestamp must explicitly use UTC')
		}
	}
	clock = clock.replace(',', '.')
	fraction := if clock.contains('.') { clock.all_after('.') } else { '' }
	if clock.contains('.') && (fraction == '' || !fraction.bytes().all(it.is_digit())) {
		return error(context + ': invalid timestamp')
	}
	clock = clock.all_before('.')
	if clock.contains(':') && clock.split(':').any(it.len != 2) {
		return error(context + ': invalid timestamp')
	}
	digits := clock.replace(':', '')
	if digits.len !in [2, 4, 6] || !digits.bytes().all(it.is_digit()) {
		return error(context + ': invalid timestamp')
	}
	micro := (fraction + '000000')[..6].int()
	if date[..4].int() == 0 { return error(context + ': invalid timestamp') }
	minute := if digits.len >= 4 { digits[2..4] } else { '00' }
	second := if digits.len == 6 { digits[4..] } else { '00' }
	normalized := '${date[..4]}-${date[4..6]}-${date[6..]}T${digits[..2]}:${minute}:${second}.${micro:06}Z'
	return time.parse_iso8601(normalized) or { return error(context + ': invalid timestamp') }
}

fn (ctx Context) campaign() ![]b.Config {
	text := os.read_file(ctx.here + '/campaign-plan.json')!
	if ctx.profile.plan != '' && archive.digest(text) != ctx.profile.plan {
		return error('campaign-plan.json bytes differ from the immutable predeclaration')
	}
	plan := object(ctx.here + '/campaign-plan.json')!
	for field, expected in {
		'order':         strings(order)
		'source_sha256': b.Value(source_sha)
		'iterations':    num(200000)
		'samples':       num(7)
		'warmup':        b.Value('full per workload')
		'common_qemu':   b.Value(qemu())
	} {
		if !b.equal(b.value(plan, field), expected) {
			return error('campaign plan differs from the predeclared four-capture configuration')
		}
	}
	mut previous := utc_time(b.value(plan, 'declared_utc'), 'campaign declaration')!
	mut records := []b.Config{}
	for name in order {
		mut record := object(ctx.here + '/' + name + '/driver-exit.json')!
		code := b.value(record, 'exit_code')
		if code !is b.Number || (code as b.Number).text.contains_any('.eE') || !b.equal(code, num(0)) {
			return error('${name}: actual driver exit zero required')
		}
		string_list(b.value(record, 'argv')) or { return error('${name}: complete driver argv required') }
		started := utc_time(b.value(record, 'started_utc'), '${name} start')!
		finished := utc_time(b.value(record, 'finished_utc'), '${name} finish')!
		if started.unix_micro() < previous.unix_micro() || finished.unix_micro() <= started.unix_micro() {
			return error('${name}: driver order, declaration time or nonoverlap check failed')
		}
		previous = finished
		record['capture'] = b.Value(name)
		records << record
	}
	return records
}

pub struct Observation {
pub:
	cohort      string
	sample      int
	pairs       u64
	elapsed_ns  u64
	ns_per_pair f64
}

pub struct Distribution {
pub:
	sample_count       int
	median_ns_per_pair f64
	min_ns_per_pair    f64
	max_ns_per_pair    f64
	observations       []Observation
}

pub struct Row {
pub:
	workload            string
	vinix               Distribution
	catalina            Distribution
	vinix_over_catalina f64
	vinix_at_or_faster  bool
}

pub struct Cohort {
pub:
	cohort                     int
	vinix_meta                 map[string]string
	catalina_meta              map[string]string
	notes                      []string
	workloads                  []Row
	all_workloads_at_or_faster bool
}

pub struct Report {
pub:
	cohort_count                      int
	campaign_drivers                  []b.Config
	cohorts                           []Cohort
	pooled_workloads                  []Row
	all_cohorts_at_or_faster          bool
	all_pooled_workloads_at_or_faster bool
	method                            string
	vinix_provenance                  b.Config
}

fn distribution(runs []b.Run, workload string) Distribution {
	mut observations := []Observation{}
	mut values := []f64{}
	for run in runs {
		pairs := run.results[workload]['pairs'].u64()
		for sample in run.samples[workload] {
			elapsed := sample['elapsed_ns'].u64()
			ratio := b.ratio(elapsed, pairs)
			observations << Observation{run.name, sample['sample'].int(), pairs, elapsed, ratio}
			values << ratio
		}
	}
	values.sort()
	center := values.len / 2
	median := if values.len % 2 != 0 {
		values[center]
	} else {
		(values[center - 1] + values[center]) / 2
	}
	return Distribution{values.len, median, values[0], values.last(), observations}
}

fn rows(vinix []b.Run, catalina []b.Run) []Row {
	mut result := []Row{}
	for workload in b.workloads {
		left := distribution(vinix, workload.name)
		right := distribution(catalina, workload.name)
		ratio := left.median_ns_per_pair / right.median_ns_per_pair
		result << Row{workload.name, left, right, ratio, ratio <= 1}
	}
	return result
}

pub fn (ctx Context) recompute() !Report {
	archive.checkpoint()!
	ctx.validator() or { return error('Cannot load saved strict validator: ' + err.msg()) }
	if numbered(ctx.here, 'vinix')! != [1, 2] || numbered(ctx.here, 'catalina')! != [
		1,
		2,
	] {
		return error('exactly the declared vinix-1/2 and catalina-1/2 final captures are required')
	}
	drivers := ctx.campaign()!
	snapshots := object(ctx.here + '/source-snapshots.json')!
	for name in ['bench.c', 'compare.py'] {
		record := obj(b.value(snapshots, name), 'preserved ${name} differs from source-snapshots.json')!
		expected := if name == 'bench.c' { source_sha } else { legacy_compare_sha }
		if !b.equal(b.value(record, 'sha256'), b.Value(expected)) || archive.digest(ctx.preserved_source(name)!) != expected {
			return error('preserved ${name} differs from source-snapshots.json')
		}
	}
	p := ctx.profile
	kernel := object(ctx.here + '/validation/kernel-x86_64.json')!
	if !b.equal(b.value(kernel, 'kernel_sha256'), b.Value(p.kernel)) {
		return error('saved final kernel provenance must match the approved ${if p.version == 'v4' {
			'v4'
		} else {
			'v5'
		}} kernel')
	}
	builds := object(ctx.here + '/validation/libc-builds.json')!
	build_key := 'optimized-${p.version}-final'
	optimized := obj(b.value(builds, build_key), 'saved ${build_key} libc build manifest required')!
	expected := obj(b.value(optimized, 'manifest'), 'saved ${build_key} libc build manifest required')!
	mut patches := []b.Value{}
	list := b.value(expected, 'patches')
	if list is []b.Value {
		for item in list {
			if item is map[string]b.Value {
				if b.equal(b.value(item, 'name'), b.Value('malloc-retain.patch')) {
					patches << b.value(item, 'sha256')
				}
			}
		}
	}
	if !b.equal(b.value(expected, 'libc_so_sha256'), b.Value(p.loader)) || !b.equal(b.value(expected, 'libc_a_sha256'), b.Value(p.static_hash)) || !b.equal(b.value(expected, 'retention'), num(1)) || !b.equal(b.value(expected, 'arch'), b.Value('x86_64')) || !b.equal(b.value(expected, 'version'), b.Value('1.2.5')) || !b.equal(b.Value(patches), strings([p.patch])) || archive.digest(os.read_file(ctx.here + '/validation/libc.patch')!) != p.patch {
		return error('saved ${build_key} provenance differs from final ${p.patch[..4]} libc artifacts')
	}
	mut vinix := []b.Run{}
	mut catalina := []b.Run{}
	mut cohorts := []Cohort{}
	for number in [1, 2] {
		v := b.read_run('${ctx.here}/vinix-${number}/serial.log', '${ctx.here}/vinix-${number}/config.json', 'vinix-${number}')!
		m := b.read_run('${ctx.here}/catalina-${number}/serial.log', '${ctx.here}/catalina-${number}/config.json', 'catalina-${number}')!
		mismatches, notes := b.comparability(v, m)
		if mismatches.len > 0 { return error('cohort ${number}: ' + mismatches.join('; ')) }
		validate_manifest(v)!
		validate_manifest(m)!
		if !b.equal(b.value(v.config, 'source_sha256'), b.Value(source_sha)) {
			return error('cohort ${number}: benchmark source hash differs from bench.c')
		}
		for key in ['kernel_sha256', 'libc_sha256', 'libc_a_sha256'] {
			if !b.sha(b.value(v.config, key)) { return error('${v.name}: valid ${key} required') }
		}
		if !b.equal(b.value(v.config, 'kernel_sha256'), b.value(kernel, 'kernel_sha256')) {
			return error('${v.name}: kernel hash differs from saved final validation provenance')
		}
		build := obj(b.value(v.config, 'libc_build'), '${v.name}: libc build manifest must be a JSON object')!
		if !b.equal(b.value(build, 'libc_so_sha256'), b.value(v.config, 'libc_sha256')) || !b.equal(b.value(build, 'libc_a_sha256'), b.value(v.config, 'libc_a_sha256')) {
			return error('${v.name}: libc file hashes disagree with build manifest')
		}
		if !b.equal(b.Value(build), b.Value(expected)) {
			return error('${v.name}: libc build differs from saved ${build_key} validation provenance')
		}
		for key in ['assembly_sha256', 'binary_sha256', 'freshly_verified_assembly_sha256'] {
			if !b.sha(b.value(m.config, key)) { return error('${m.name}: valid ${key} required') }
		}
		if !b.equal(b.value(m.config, 'assembly_sha256'), b.value(m.config, 'freshly_verified_assembly_sha256')) {
			return error('${m.name}: freshly generated guest assembly differs from linked assembly')
		}
		vinix << v
		catalina << m
		measurements := rows([v], [m])
		cohorts << Cohort{number, v.meta, m.meta, notes, measurements, measurements.all(it.vinix_at_or_faster)}
	}
	for field in provenance_fields { require_same(vinix, field)! }
	mut common_fields := b.config_fields.clone()
	common_fields << 'compile_flags'
	mut all_runs := vinix.clone()
	all_runs << catalina
	for field in common_fields { require_same(all_runs, field)! }
	for field in ['assembly_sha256', 'binary_sha256', 'freshly_verified_assembly_sha256',
		'guest_compile_command', 'host_link_command', 'sdk', 'build_method', 'build_mode',
		'guest_version'] {
		require_same(catalina, field)!
	}
	for runs in [vinix, catalina] {
		for run in runs[1..] {
			mut fields := b.meta_fields.clone()
			fields << ['platform', 'release', 'compiler', 'compiler_major', 'compiler_minor',
				'compiler_patch', 'compiler_version']
			for field in fields {
				if run.meta[field] != runs[0].meta[field] {
					return error('${run.name}: ${field} differs between final cohorts')
				}
			}
		}
	}
	pooled := rows(vinix, catalina)
	mut provenance := b.Config{}
	for key in provenance_fields { provenance[key] = b.value(vinix[0].config, key) }
	return Report{cohorts.len, drivers, cohorts, pooled, cohorts.all(it.all_workloads_at_or_faster), pooled.all(it.vinix_at_or_faster), method, provenance}
}

fn fixed6(value f64) string {
	mut buffer := [384]u8{}
	count := unsafe { C.snprintf(&char(&buffer[0]), usize(buffer.len), c'%.6f', value) }
	return buffer[..int(count)].bytestr()
}

fn formatted(item Distribution) string {
	return b.fixed(item.median_ns_per_pair) + ' [' + b.fixed(item.min_ns_per_pair) + ', ' + b.fixed(item.max_ns_per_pair) + ']'
}

fn table(title string, measurements []Row) []string {
	mut output := [title, '',
		'| Workload | Samples/guest | Vinix ns/pair median [min, max] | Catalina ns/pair median [min, max] | Vinix/Catalina | At or faster |',
		'| --- | ---: | ---: | ---: | ---: | --- |']
	for row in measurements {
		output << '| ${row.workload} | ${row.vinix.sample_count}/${row.catalina.sample_count} | ${formatted(row.vinix)} | ${formatted(row.catalina)} | ${fixed6(row.vinix_over_catalina)} | ${if row.vinix_at_or_faster {
			'yes'
		} else {
			'no'
		}} |'
	}
	output << ''
	return output
}

pub fn (report Report) markdown() string {
	mut output := [report.method, '']
	for cohort in report.cohorts {
		output << table('Cohort ${cohort.cohort}', cohort.workloads)
		output << cohort.notes
		output << ''
	}
	output << table('Pooled samples from every final cohort', report.pooled_workloads)
	output << 'All individual cohorts at or faster: ${if report.all_cohorts_at_or_faster {
		'True'
	} else {
		'False'
	}}.'
	output << 'All pooled workloads at or faster: ${if report.all_pooled_workloads_at_or_faster {
		'True'
	} else {
		'False'
	}}.'
	return output.join('\n') + '\n'
}

pub fn run(root string, here string, campaign string, args []string) int {
	mut as_json := false
	for arg in args {
		if arg in ['-h', '--help'] {
			println('usage: recompute [-h] [--json]\n\nValidate every numbered final cohort and recompute all raw sample statistics.')
			return 0
		}
		if arg.len > 2 && '--json'.starts_with(arg) {
			as_json = true
		} else {
			eprintln('recompute: error: unrecognized arguments: ' + arg)
			return 2
		}
	}
	guard := archive.own_commands()
	defer { guard.close() }
	ctx := context(root, here, campaign) or {
		eprintln('Cannot load saved strict validator: ${err}')
		return if err.code() in [130, 143] { err.code() } else { 1 }
	}
	result := ctx.recompute() or {
		eprintln('Cannot recompute: ${err}')
		return if err.code() in [130, 143] { err.code() } else { 1 }
	}
	if as_json { println(json2.encode(result, prettify: true)) } else { print(result.markdown()) }
	return 0
}
