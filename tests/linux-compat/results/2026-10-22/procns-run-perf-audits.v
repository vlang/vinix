import os

const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

fn main() {
 assert os.args.len == 2 && os.args[1] in ['results', 'inputs', 'drag']
 results := os.args[1] == 'results'
 executable := if results { 'verify-perf-results' } else if os.args[1] == 'drag' { 'verify-perf-drag' } else { 'verify-perf' }
 name := if results { 'perf-results-audit' } else if os.args[1] == 'drag' { 'perf-drag-audit' } else { 'perf-post-inputs-audit' }
 mut p := os.new_process(area + '/' + executable)
 p.set_redirect_stdio_merged()
 p.run()
 output := p.stdout_slurp()
 p.wait()
 code := p.code
 p.close()
 os.write_file(area + '/' + name + '.log', output)!
 os.write_file(area + '/' + name + '.status', code.str() + '\n')!
 print(output)
 exit(code)
}
