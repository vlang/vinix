from pathlib import Path
import datetime,json,subprocess,sys
root=Path(__file__).resolve().parent.parent
state=root/"build"/sys.argv[1]
log=state.with_suffix(".runner.log")
command=[sys.executable,str(root/"tests/alloc-bench/run-vinix.py"),"--kernel",str(Path(sys.argv[3]).resolve()),"--sysroot",str(root/"third_party/useralloc-libc/build/useralloc"/sys.argv[2]),"--state-dir",str(state),"--iterations","200000","--samples","7","--timeout","3600"]
kernel=Path(sys.argv[3]).resolve()
if not kernel.is_file(): raise SystemExit(f"kernel missing: {kernel}")
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
with log.open("wb") as output:
    result=subprocess.run(command,cwd=root,stdout=output,stderr=subprocess.STDOUT)
record={"argv":command,"started_utc":started,"finished_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"exit_code":result.returncode}
state.with_suffix(".exit.json").write_text(json.dumps(record,indent=2)+"\n")
raise SystemExit(result.returncode)
