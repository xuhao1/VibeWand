"""Play a known stimulus and save four local captures; close the app first."""
import pathlib
import subprocess
import time

root=pathlib.Path(__file__).resolve().parents[3]/'output'/'dualsense-mic'
app=root/'VibeWand Mic.app/Contents/MacOS/VibeWandMic'
conditions=[('queue-legacy-stress',['--legacy-main-input','--stress-ui']),
            ('queue-worker-stress',['--stress-ui']),
            ('queue-worker-normal',[]),
            ('queue-legacy-normal',['--legacy-main-input'])]
for name,extra in conditions:
    logpath=root/f'acoustic-{name}.txt'
    with logpath.open('w') as logfile:
        process=subprocess.Popen([str(app),'--test-seconds','32','--capture-system']+extra,
                                 cwd=root,stdout=logfile,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            started=time.monotonic()
            while time.monotonic()-started<12:
                text=logpath.read_text()
                if 'Audio stream ready' in text:break
                if 'failed:' in text or process.poll() is not None:raise RuntimeError(text)
                time.sleep(.1)
            else:raise RuntimeError('No live microphone reports; no stimulus played')
            print(name,'audio ready',flush=True)
            time.sleep(3)
            subprocess.run(['/usr/bin/afplay','-v','1.0',str(root/'stimulus.wav')],check=True)
            while time.monotonic()-started<42:
                text=logpath.read_text()
                if 'System recording samples=' in text:break
                if process.poll() is not None:raise RuntimeError('App ended early: '+text)
                time.sleep(.1)
            else:raise RuntimeError('Capture cleanup did not complete')
            for src,suffix in [('microphone-test.wav','raw'),('system-microphone-test.wav','system')]:
                (root/f'acoustic-{name}-{suffix}.wav').write_bytes((root/src).read_bytes())
            print(name,text,flush=True)
        finally:
            if process.poll() is None:
                process.terminate()
                # Do not force kill: the app must restore its temporary Game Mode policy.
                process.wait(timeout=10)
print('Queue comparison complete; all captures stopped',flush=True)
