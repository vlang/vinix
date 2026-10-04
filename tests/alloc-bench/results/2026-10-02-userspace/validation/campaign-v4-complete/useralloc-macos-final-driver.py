from pathlib import Path
import datetime,json,subprocess,sys
root=Path(__file__).resolve().parent.parent
state=root/"build"/sys.argv[1]
command=[sys.executable,str(root/"build/useralloc-macos-runtime/measure.py"),str(state)]
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
with state.with_suffix(".runner.log").open("wb") as output:
    result=subprocess.run(command,cwd=root,stdout=output,stderr=subprocess.STDOUT)
state.with_suffix(".exit.json").write_text(json.dumps({"argv":command,"started_utc":started,"finished_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"exit_code":result.returncode},indent=2)+"\n")
raise SystemExit(result.returncode)
