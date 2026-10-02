from pathlib import Path
import importlib.util, json
s=Path(__file__).resolve().parent
root=s if (s/'driver.py').exists() else s.parent
spec=importlib.util.spec_from_file_location('core_driver',root/'driver.py')
d=importlib.util.module_from_spec(spec);spec.loader.exec_module(d)
if s==root: d.main()
else:
    mode=s.name.removeprefix('core-') if hasattr(s.name,'removeprefix') else s.name[5:]
    arch='aarch64' if mode=='aarch64' else 'x86_64'
    base=json.loads((root/f'core-{arch}'/'compile.json').read_text())
    image=json.loads((root/'core-x86_64/embedded-input-check.json').read_text())
    result=d.run_mode(mode,base,image)
    raise SystemExit(result['exit_code'])
