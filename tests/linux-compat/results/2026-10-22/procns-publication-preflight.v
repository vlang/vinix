import crypto.sha256
import json2
import os

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 mut seen := map[string]string{}
 mut present := 0
 mut missing := 0
 for name in ['publication-map.json', 'perf-publication-inputs.json', 'desktop-publication-inputs.json', 'x86-regressions-publication-inputs.json', 'queue-publication-inputs.json', 'queue-perf-publication-inputs.json', 'queue-desktop-publication-inputs.json'] {
  if !os.is_file(area + '/' + name) { println('Pending map: ' + name); continue }
  entries := json2.decode[map[string]string](os.read_file(area + '/' + name)!)!
  mut absent := 0
  for suffix, path in entries {
   assert suffix != '' && !suffix.contains('/') && !suffix.contains('..')
   if !os.is_file(path) { missing++; absent++; continue }
   hash := sha256.sum(os.read_bytes(path)!).hex()
   if prior := seen[suffix] { assert prior == hash, 'Different sources for ' + suffix }
   seen[suffix] = hash
   present++
  }
  println('${name}: ${entries.len} entries, ${absent} pending')
 }
 println('Publication preflight: ${present} present, ${missing} pending, ${seen.len} unique names; no conflicting contents')
}
