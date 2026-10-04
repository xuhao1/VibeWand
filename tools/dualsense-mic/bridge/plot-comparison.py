import json,re
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=Path(__file__).resolve().parents[3]/'output'/'dualsense-mic'
names=['baseline','boosted'];labels=['Default Bluetooth policy','Game Mode enabled'];colors=['#dd7637','#008f86']
metrics=[];gaps=[];curves=[]
_,x=wavfile.read(root/'stimulus.wav');x=x.astype(float)/32768
for name in names:
 j=json.load(open(root/f'analysis-{name}-system/metrics.json'))
 j['median_abs_peak_correlation']=float(np.median([abs(b['correlation']) for b in j['block_matches']]))
 (root/f'analysis-{name}-system/metrics.json').write_text(json.dumps(j,indent=2)+'\n')
 metrics.append(j)
 log=(root/f'acoustic-{name}.txt').read_text();m=re.search(r'frames=(\d+) missing=(\d+)',log);n,miss=map(int,m.groups());gaps.append(miss/(n+miss)*100)
 _,y=wavfile.read(root/f'acoustic-{name}-system.wav');y=y.astype(float)/32768
 start=round(j['alignment_offset_ms']/1000*48000)+4*48000
 ref=x[4*48000:14*48000];rec=y[start:start+len(ref)]
 f,c=signal.coherence(ref,rec,fs=48000,nperseg=4096);curves.append((f,c))
fig=plt.figure(figsize=(11,8),layout='constrained');grid=fig.add_gridspec(3,2,height_ratios=[1,1.4,1.4])
a=fig.add_subplot(grid[0,0]);a.bar(labels,gaps,color=colors);a.set(ylabel='Missing frames (%)',ylim=(0,70));
for i,v in enumerate(gaps):a.text(i,v+1.5,f'{v:.1f}%',ha='center',fontweight='bold')
a=fig.add_subplot(grid[0,1]);values=[j['median_abs_peak_correlation'] for j in metrics];a.bar(labels,values,color=colors);a.set(ylabel='Peak |correlation|',ylim=(0,1));
for i,v in enumerate(values):a.text(i,v+.025,f'{v:.3f}',ha='center',fontweight='bold')
a=fig.add_subplot(grid[1,:]);
for (f,c),label,color in zip(curves,labels,colors):a.plot(f,c,label=label,color=color,lw=1.3)
a.set(xlim=(300,3400),ylim=(0,1),xlabel='Frequency (Hz)',ylabel='Magnitude-squared coherence');a.legend();a.grid(alpha=.25)
a=fig.add_subplot(grid[2,:]);
for j,label,color in zip(metrics,labels,colors):a.plot([b['reference_second'] for b in j['block_matches']],[abs(b['correlation']) for b in j['block_matches']],'o-',label=label,color=color)
a.set(xlabel='Reference playback time (s)',ylabel='Peak |correlation|',ylim=(0,1));a.grid(alpha=.25);a.legend()
fig.suptitle('DualSense microphone: acoustic A/B test\nSame signal, position and gain; environmental noise present; concealment in both runs',fontsize=14)
fig.savefig(root/'acoustic-comparison.png',dpi=150)
report={name:{'application_missing_percent':gap,'median_abs_peak_correlation':j['median_abs_peak_correlation'],'median_band_coherence':j['median_300_3400Hz_coherence'],'estimated_test_to_background_db':j['estimated_test_to_background_db'],'clipped_fraction':j['clipped_fraction']} for name,gap,j in zip(names,gaps,metrics)}
report['system_path']=json.load(open(root/'pipeline-check.json'))
report['limitations']=['One device and one noisy acoustic setup; not a calibrated audio-quality benchmark.','Missing frames are application-visible sequence gaps, not measured over-the-air packet loss.','Opus concealment fills missing time with estimates and cannot recover the original missing samples.','Alignment offsets include recording-start differences; they are not standalone Bluetooth latency measurements.']
(root/'comparison.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
