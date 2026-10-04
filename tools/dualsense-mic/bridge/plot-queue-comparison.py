"""Render the recorded, metadata-only queue comparison."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=Path(__file__).resolve().parents[3]
d=json.loads((root/'docs/dualsense-microphone-timing-results.json').read_text())
a,b=d['queue_comparison'][:2]
fig,axes=plt.subplots(1,3,figsize=(11,3.8),layout='constrained')
for ax,key,title in zip(axes,['underruns','median_300_3400Hz_coherence','missing_fraction'],['PCM buffer underruns ↓','Speech-band coherence ↑','Transport sequence gaps']):
 values=[a[key],b[key]]
 if key=='missing_fraction':values=[v*100 for v in values]
 bars=ax.bar(['Main thread','Input queue'],values,color=['#b65b56','#3c8b79'])
 ax.set_title(title,fontsize=11)
 ax.bar_label(bars,labels=[f'{v:.2f}'+('%' if key=='missing_fraction' else '') for v in values],padding=3)
 ax.set_ylim(0,max(values)*1.25)
 ax.spines[['top','right']].set_visible(False)
fig.suptitle('250 ms UI stall every 2 seconds · 32-second capture',fontsize=13)
fig.savefig(root/'docs/images/dualsense-microphone-queue-comparison.png',dpi=160)
