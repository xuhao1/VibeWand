import subprocess,time,pathlib
root=pathlib.Path(__file__).resolve().parents[3]/'output'/'dualsense-mic'
app=root/'VibeWand Mic.app/Contents/MacOS/VibeWandMic'
for name,extra in [('baseline',['--no-game-mode']),('boosted',[])]:
    logpath=root/f'acoustic-{name}.txt'
    f=logpath.open('w')
    p=subprocess.Popen([str(app),'--test-seconds','32','--capture-system']+extra,cwd=root,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
    (root/'acoustic-app.pid').write_text(str(p.pid))
    started=time.monotonic()
    while time.monotonic()-started<12:
        text=logpath.read_text()
        if 'Audio stream ready' in text:break
        if 'failed:' in text or p.poll() is not None:raise RuntimeError(text)
        time.sleep(.1)
    else:raise RuntimeError('No live microphone reports; no test audio played')
    print(name,'audio ready',flush=True)
    time.sleep(3)
    subprocess.run(['/usr/bin/afplay','-v','1.0',str(root/'stimulus.wav')],check=True)
    while time.monotonic()-started<42:
        text=logpath.read_text()
        if 'System recording samples=' in text:break
        if p.poll() is not None:raise RuntimeError('App ended early: '+text)
        time.sleep(.1)
    else:raise RuntimeError('Capture cleanup did not complete')
    for src,dst in [('microphone-test.wav',f'acoustic-{name}-raw.wav'),('system-microphone-test.wav',f'acoustic-{name}-system.wav')]:
        (root/dst).write_bytes((root/src).read_bytes())
    print(name,text,flush=True)
    f.close()
    if name=='baseline':
        p.terminate();p.wait(timeout=8)
        print('baseline graceful shutdown passed',flush=True)
print('A/B captures complete; boosted app remains idle',flush=True)
