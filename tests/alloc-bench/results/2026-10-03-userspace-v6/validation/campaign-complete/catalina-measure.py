from pathlib import Path
import json, socket, subprocess, sys, time
runtime=Path(__file__).resolve().parent
state=Path(sys.argv[1]).resolve(); state.mkdir(parents=True,exist_ok=False)
console=runtime/'console.log'; offset=console.stat().st_size
config=json.loads(Path('tests/alloc-bench/results/2026-10-02/user-macos/config.json').read_text())
config.update(argv=json.loads((runtime/'argv.json').read_text()), iterations=200000, samples=7,
              guest_compile_command=config['guest_compile_command'].replace('/tmp/bench-native.s','/tmp/bench-native-fresh.s'),
              freshly_verified_assembly_sha256='ff4f96b50b88ea1482866c7fed1bbc0750d46e47c0f984466332615439136bdd',
              binary_reused_after_matching_fresh_guest_codegen=True,
              started_utc=subprocess.check_output(['date','-u','+%Y-%m-%dT%H:%M:%SZ'],text=True).strip(),
              transport='private serial console in single-user mode')
(state/'config.json').write_text(json.dumps(config,indent=2)+'\n')
s=socket.socket(socket.AF_UNIX); s.settimeout(5); s.connect(str(runtime/'qmp.sock')); f=s.makefile('rb'); json.loads(f.readline())
def qmp(command):
 s.sendall((json.dumps({'execute':command})+'\n').encode())
 while True:
  msg=json.loads(f.readline())
  if 'return' in msg: return msg['return']
  if 'error' in msg: raise RuntimeError(msg)
qmp('qmp_capabilities'); qmp('cont')
with (runtime/'commands.txt').open('a') as out:
 out.write('/tmp/alloc-bench-native --label macos --iterations 200000 --samples 7\n')
try:
 deadline=time.monotonic()+3600
 last=''
 while time.monotonic()<deadline:
  with console.open('rb') as inp:
   inp.seek(offset); data=inp.read()
  (state/'serial.log').write_bytes(data)
  text=data.decode(errors='replace')
  results=[line.strip() for line in text.splitlines() if line.strip().startswith('ALLOC-RESULT')]
  if results and results[-1]!=last:
   last=results[-1]; print(last,flush=True)
  if 'ALLOC-ERROR' in text or 'ALLOC-FAIL' in text: raise RuntimeError('macOS benchmark failed')
  if 'ALLOC-DONE' in text:
   print('macOS benchmark complete',flush=True); break
  time.sleep(.25)
 else: raise RuntimeError('macOS benchmark timeout; guest may still be running')
finally:
 qmp('stop'); s.close()
