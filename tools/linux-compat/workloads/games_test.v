module main

fn test_doom_benchmark_exit_requires_completed_gameplay() {
 result := CommandResult{exit_code: 255, stderr: 'timed 1710 gametics in 45 realtics (1330.000000 fps)\n\n'}
 ticks, real := doom_timing(result)!
 assert ticks == 1710 && real == 45
 for invalid in [
  CommandResult{...result, exit_code: 0},
  CommandResult{...result, exit_code: 139},
  CommandResult{...result, timed_out: true},
  CommandResult{...result, output_limited: true},
  CommandResult{...result, stderr: 'Failed to initialize SDL video\n'},
  CommandResult{...result, stderr: 'timed 0 gametics in 45 realtics (0.000000 fps)\n'},
  CommandResult{...result, stderr: 'timed 1710 gametics in 0 realtics (inf fps)\n'},
 ] {
  doom_timing(invalid) or { continue }
  assert false, 'accepted an incomplete or failed game benchmark'
 }
}
