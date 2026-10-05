import os,pty,select,time,json,hashlib
from pathlib import Path
root=Path('/Users/alex/code/vinix');src=root/'third_party/useralloc-vm-next';state=root/'build/useralloc-arm-v5-final'
env=dict(os.environ,VINIX_INITRAMFS=str(state/'initramfs.tar'),VINIX_KERNEL_DIR=str(state/'kernel'),VINIX_BOOT_DISK=str(state/'boot.img'),VINIX_BOOT_DISK_SIZE_MB='128',VINIX_EFIVARS=str(state/'vars.fd'),VINIX_QEMU_PACKAGE_STORE=str(state/'packages.tar'),VINIX_QEMU_PERSIST='0',VINIX_QEMU_HOST_SOURCE='0',VINIX_QEMU_AUDIO='off',VINIX_QEMU_SMP='2',VINIX_KEEP_TEMP_BOOT_DISK='1',USE_TCG='0')
command=[str(src/'scripts/run-aarch64.sh'),'--no-build','--serial','--mem=2048','--guest-init='+str(state/'rootfs/sbin/init'),'--no-persist']
manifest={'command':command,'environment':{k:v for k,v in env.items() if k.startswith('VINIX_') or k=='USE_TCG'},'kernel_sha256':hashlib.sha256((state/'kernel/bin/vinix').read_bytes()).hexdigest(),'initramfs_sha256':hashlib.sha256((state/'initramfs.tar').read_bytes()).hexdigest()}
(state/'run.json').write_text(json.dumps(manifest,indent=2)+'\n')
pid,master=pty.fork()
if pid==0:
    os.chdir(src);os.execve(command[0],command,env)
transcript=bytearray();status=None;done=False
try:
    deadline=time.monotonic()+900
    with (state/'serial.log').open('wb') as logfile:
        while time.monotonic()<deadline:
            waited,child=os.waitpid(pid,os.WNOHANG)
            if waited==pid:status=child;break
            ready,_,_=select.select([master],[],[],0.25)
            if ready:
                try:chunk=os.read(master,65536)
                except OSError:continue
                transcript.extend(chunk);logfile.write(chunk);logfile.flush()
                if b'UALLOC-ARM-DONE' in chunk or b'UALLOC-ARM-DONE' in transcript[-4096:]:done=True;break
                if b'KERNEL PANIC' in transcript[-16384:]:break
finally:
    if status is None:
        try:os.write(master,b'\x01x')
        except OSError:pass
        until=time.monotonic()+5
        while time.monotonic()<until:
            waited,child=os.waitpid(pid,os.WNOHANG)
            if waited==pid:status=child;break
            time.sleep(.05)
        if status is None:
            import signal
            try: os.kill(pid,signal.SIGTERM)
            except (ProcessLookupError, PermissionError): pass
            until=time.monotonic()+2
            while time.monotonic()<until:
                try: waited,child=os.waitpid(pid,os.WNOHANG)
                except ChildProcessError: break
                if waited==pid:status=child;break
                time.sleep(.05)
    os.close(master)
text=transcript.decode(errors='replace');markers=[line for line in text.splitlines() if line.startswith('UALLOC-')]
for line in markers:print(line)
passed=done and text.count('UALLOC-DONE checks=')==4 and text.count('UALLOC-ARM-PASS program=')==9 and text.count('UALLOC-SUPPLEMENT-DONE checks=')==4 and text.count('UALLOC-ALL-CLASSES ')==4 and text.count('UALLOC-THREAD-TRANSITIONS ')==4 and 'CLOCK-DONE' in text and not any(x in text for x in ['UALLOC-FAIL','UALLOC-ARM-FAIL','CLOCK-FAIL','KERNEL PANIC'])
manifest.update({'passed':passed,'completed_cases':text.count('UALLOC-DONE checks='),'supplemental_cases':text.count('UALLOC-SUPPLEMENT-DONE checks='),'markers':markers,'serial_sha256':hashlib.sha256((state/'serial.log').read_bytes()).hexdigest()})
(state/'run.json').write_text(json.dumps(manifest,indent=2)+'\n')
raise SystemExit(0 if passed else 1)
