"""Summarize metadata-only probe traces; no microphone samples are read."""
import csv,json,sys
from pathlib import Path

def percentile(values,p):
    values=sorted(values)
    return values[min(len(values)-1,int((len(values)-1)*p))] if values else None

def analyze(path):
    rows=list(csv.DictReader(path.open()))
    inputs=[r for r in rows if r['event']=='input']
    mic=[r for r in inputs if int(r['mic'])>=0]
    writes=[r for r in rows if r['event']=='write' and r['on']=='1']
    if len(mic)<2:return {'path':str(path),'error':'Not enough microphone reports'}
    start,end=float(mic[0]['time']),float(mic[-1]['time'])
    active=[r for r in inputs if start<=float(r['time'])<=end]
    gaps=[];deltas={};toc={};report_deltas={}
    for r in mic:toc[r['toc']]=toc.get(r['toc'],0)+1
    for a,b in zip(active,active[1:]):
        d=(int(b['report'])-int(a['report']))&15
        report_deltas[d]=report_deltas.get(d,0)+1
    for a,b in zip(mic,mic[1:]):
        d=(int(b['mic'])-int(a['mic']))&255
        deltas[d]=deltas.get(d,0)+1
        if 1<d<128:
            t=float(b['time']); prior=[float(w['time']) for w in writes if float(w['time'])<=t]
            gaps.append({'missing':d-1,'arrival_ms':(t-float(a['time']))*1000,'since_write_ms':(t-max(prior))*1000 if prior else None})
    missing=sum(g['missing'] for g in gaps)
    arrivals=[(float(b['time'])-float(a['time']))*1000 for a,b in zip(active,active[1:])]
    durations=[float(r['duration'])*1000 for r in mic]
    return {'path':str(path),'frames':len(mic),'missing':missing,'missing_fraction':missing/(len(mic)+missing),'seconds':end-start,'report_rate':(len(active)-1)/(end-start),'mic_deltas':deltas,'report_deltas':report_deltas,'toc':toc,'gap_count':len(gaps),'max_gap_ms':max([g['missing']*10 for g in gaps],default=0),'input_interval_ms_p50':percentile(arrivals,.5),'input_interval_ms_p99':percentile(arrivals,.99),'decode_callback_ms_p99':percentile(durations,.99),'decode_callback_ms_max':max(durations),'write_ms_p99':percentile([float(r['duration'])*1000 for r in writes],.99),'gaps':gaps}
if __name__=='__main__':
    print(json.dumps([analyze(Path(p)) for p in sys.argv[1:]],indent=2))
