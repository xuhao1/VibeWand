"""Known acoustic stimulus and local capture analysis. Never uploads audio."""
import argparse, json
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
RATE=48000

def stimulus(path):
    rng=np.random.default_rng(405)
    n=21*RATE
    y=np.zeros(n)
    sos=signal.butter(5,[300,3400],btype='bandpass',fs=RATE,output='sos')
    noise=signal.sosfilt(sos,rng.standard_normal(10*RATE))
    noise=noise/max(abs(noise))*0.16
    y[4*RATE:14*RATE]=noise
    for start,duration,f0,f1 in [(1,2,300,5500),(18,2,5500,300)]:
        t=np.arange(duration*RATE)/RATE
        y[start*RATE:(start+duration)*RATE]=0.075*signal.chirp(t,f0,duration,f1,method='logarithmic')*signal.windows.tukey(len(t),0.05)
    t=np.arange(3*RATE)/RATE
    y[14*RATE:17*RATE]=sum(0.025*np.sin(2*np.pi*f*t) for f in (440,880,1760))*signal.windows.tukey(len(t),0.05)
    wavfile.write(path,RATE,(y*32767).astype(np.int16))

def read(path):
    rate,y=wavfile.read(path)
    if y.dtype==np.int16:y=y.astype(float)/32768
    elif y.dtype==np.int32:y=y.astype(float)/2147483648
    else:y=y.astype(float)
    if y.ndim>1:y=y.mean(axis=1)
    if rate != RATE:y=signal.resample_poly(y,RATE,rate)
    return y

def analyze(reference,capture,out):
    x=read(reference);y=read(capture)
    # Downsample only for delay estimation; preserve full-band samples for spectral QA.
    xd=signal.resample_poly(x,1,8);yd=signal.resample_poly(y,1,8)
    corr=signal.correlate(yd,xd,mode='full',method='fft')
    lag=(np.argmax(abs(corr))-(len(xd)-1))*8
    blocks=[]
    for start in range(4*RATE,14*RATE,RATE):
        r=x[start:start+RATE]
        center=start+lag
        lo=max(0,center-RATE//3);hi=min(len(y),center+RATE+RATE//3)
        piece=y[lo:hi]
        if len(piece)<len(r):continue
        cross=signal.correlate(piece,r,mode='valid',method='fft')
        power=signal.convolve(piece*piece,np.ones(len(r)),mode='valid',method='fft')
        rho=cross/np.sqrt(np.maximum(1e-15,power*np.dot(r,r)))
        peak=int(np.argmax(abs(rho)))
        blocks.append({'reference_second':start/RATE,'delay_ms':(lo+peak-start)/RATE*1000,'correlation':float(rho[peak])})
    begin=max(0,lag);end=min(len(y),lag+len(x))
    aligned=y[begin:end]
    referenceAligned=x[max(0,-lag):max(0,-lag)+len(aligned)]
    width=min(len(aligned),len(referenceAligned));aligned=aligned[:width];referenceAligned=referenceAligned[:width]
    frequencies,px=signal.welch(referenceAligned,RATE,nperseg=4096)
    _,py=signal.welch(aligned,RATE,nperseg=4096)
    delays=[b['delay_ms'] for b in blocks]
    def region(a,b):
        lo=max(0,int(lag+a*RATE));hi=min(len(y),int(lag+b*RATE));return y[lo:hi]
    quiet=np.concatenate([region(a,b) for a,b in [(0.25,.75),(3.25,3.75),(17.25,17.75),(20.25,20.75)]])
    quietBlocks=quiet[:len(quiet)//4800*4800].reshape(-1,4800)
    noisePower=float(np.median(np.mean(quietBlocks**2,axis=1)))
    activePower=float(np.mean(region(4,14)**2))
    snr=float(10*np.log10(max(1e-15,activePower-noisePower)/max(1e-15,noisePower)))
    rn=x[4*RATE:14*RATE];yn=region(4,14)
    usable=min(len(rn),len(yn))
    cf,coherence=signal.coherence(rn[:usable],yn[:usable],fs=RATE,nperseg=4096)
    medianCoherence=float(np.median(coherence[(cf>=300)&(cf<=3400)]))
    metrics={'capture_seconds':len(y)/RATE,'reference_seconds':len(x)/RATE,'alignment_offset_ms':lag/RATE*1000,
             'peak':float(np.max(abs(y))),'clipped_fraction':float(np.mean(abs(y)>=32760/32768)),
             'rms':float(np.sqrt(np.mean(y*y))),'block_matches':blocks,
             'matched_delay_spread_ms':float(max(delays)-min(delays)) if delays else None,
             'median_abs_peak_correlation':float(np.median([abs(b['correlation']) for b in blocks])) if blocks else None,
             'estimated_test_to_background_db':snr,'median_300_3400Hz_coherence':medianCoherence,
             'note':'Alignment offset includes playback start delay and acoustic path; it is not a pure Bluetooth latency. Correlation is affected by speakers, room, controller voice processing and concealment. Background SNR is a stationary-noise estimate using known silent sections, not calibrated microphone SNR.'}
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    (out/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
    fig,ax=plt.subplots(3,1,figsize=(12,9),layout='constrained')
    ax[0].plot(np.arange(width)/RATE,referenceAligned,label='Reference',alpha=.7,lw=.5)
    ax[0].plot(np.arange(width)/RATE,aligned,label='Captured (aligned)',alpha=.65,lw=.5)
    ax[0].set(xlabel='Seconds after playback alignment',ylabel='Amplitude',title='DualSense acoustic loopback');ax[0].legend()
    ax[1].semilogx(frequencies,10*np.log10(px+1e-16),label='Reference')
    ax[1].semilogx(frequencies,10*np.log10(py+1e-16),label='Captured');ax[1].set(xlim=(100,12000),xlabel='Hz',ylabel='PSD (dB/Hz)');ax[1].legend();ax[1].grid(True,alpha=.3)
    times=[b['reference_second'] for b in blocks]
    ax[2].plot(times,[abs(b['correlation']) for b in blocks],'o-',label='1-second peak absolute correlation')
    ax[2].set(xlabel='Reference second',ylabel='Peak absolute correlation',ylim=(0,1));ax[2].grid(True,alpha=.3)
    fig.savefig(out/'analysis.png',dpi=150);plt.close(fig)
    print(json.dumps(metrics,indent=2))

p=argparse.ArgumentParser();sub=p.add_subparsers(dest='mode',required=True)
s=sub.add_parser('generate');s.add_argument('path')
a=sub.add_parser('analyze');a.add_argument('reference');a.add_argument('capture');a.add_argument('output')
args=p.parse_args()
if args.mode=='generate':stimulus(args.path)
else:analyze(args.reference,args.capture,args.output)
