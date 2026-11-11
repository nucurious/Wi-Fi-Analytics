#!/usr/bin/env python3
"""Test timeline: one HTML page per run or call, from the run folders of one or two phones.

Works for every test the app runs (video call, throughput, latency, drive, walk, lab).

For each phone it lines up, on one clock:
  network (Wi-Fi name or cellular technology), signal, ping latency, throughput, battery
  temperature, and, when a screen recording is given, how often the other person's picture updated on screen, with picture stalls marked.

Usage (PC, not the phone):
  python test_timeline.py <run folder A> [<run folder B>] [-o timeline.html]

A run folder is what the app exports or `adb pull` copies: the .xlsx workbook, the
..._ScreenRec_....mp4 screen recording and, optionally, ..._summary.txt.
Instead of a folder you can give "workbook.xlsx,recording.mp4".

Needs: pip install numpy openpyxl opencv-python

How stalls are found: every frame of the recording is compared with the one before, in the
middle of the screen where the other person's picture is. Live video refreshes about once a
second even when the scene is still; a gap of 1.5 s or more with no change is a stall.
Not measured: sound, sharpness, true frame rate of a still scene.
"""
import argparse
import datetime as dt
import glob
import html
import json
import os
import re
import struct
import sys

STALL_S = 1.5          # a gap this long with no picture change is a stall
UPDATE_DIFF = 0.05     # mean absolute change (0..255) that counts as a picture update
PALETTE_LIGHT = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948']
PALETTE_DARK = ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181', '#008300', '#9085e9', '#e66767']


# ---------------------------------------------------------------- inputs

def find_inputs(arg):
    """-> (xlsx path, mp4 path or None, summary path or None)"""
    if ',' in arg and not os.path.isdir(arg):
        parts = [p.strip().strip('"') for p in arg.split(',')]
        xlsx = next((p for p in parts if p.lower().endswith('.xlsx')), None)
        mp4 = next((p for p in parts if p.lower().endswith('.mp4')), None)
        txt = next((p for p in parts if p.lower().endswith('.txt')), None)
        if not xlsx:
            sys.exit(f'No .xlsx in "{arg}"')
        return xlsx, mp4, txt
    if not os.path.isdir(arg):
        sys.exit(f'Not a folder: {arg}')
    xl = sorted(glob.glob(os.path.join(arg, '*.xlsx')))
    if not xl:
        sys.exit(f'No .xlsx workbook in {arg}')
    mp = sorted(glob.glob(os.path.join(arg, '*ScreenRec*.mp4'))) or sorted(glob.glob(os.path.join(arg, '*.mp4')))
    tx = sorted(glob.glob(os.path.join(arg, '*summary.txt')))
    if len(mp) > 1:
        mp.sort(key=os.path.getsize, reverse=True)
        print(f'  {len(mp)} recordings in {arg}; using the largest, {os.path.basename(mp[0])}')
    return xl[0], (mp[0] if mp else None), (tx[0] if tx else None)


def parse_utc(s):
    s = str(s).strip().replace('Z', '+00:00')
    m = re.match(r'(.*\.\d{6})\d+(.*)', s)   # more than 6 decimals
    if m:
        s = m.group(1) + m.group(2)
    d = dt.datetime.fromisoformat(s)
    return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)


def parse_local(s):
    return dt.datetime.fromisoformat(str(s).strip()[:19])


def num(v):
    try:
        return None if v in (None, '') else float(v)
    except (TypeError, ValueError):
        return None


def read_workbook(path):
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)

    def sheet(name):
        if name not in wb.sheetnames:
            return []
        rows = list(wb[name].iter_rows(values_only=True))
        if not rows:
            return []
        head = rows[0]
        return [dict(zip(head, r)) for r in rows[1:] if r and r[0] is not None]

    # One row per second of the run. Latency rows carry ping, Speed rows carry throughput; both carry the radio.
    # A second that has both (latency measured during a throughput test) is merged below.
    speed = sheet('Speed (per second)')
    lat = sheet('Latency (per second)')
    rows = [(r, 'lat') for r in lat] + [(r, 'speed') for r in speed]
    if not rows:
        rows = [(r, 'track') for r in sheet('GPS track')]
    if not rows:
        sys.exit(f'{os.path.basename(path)}: no "Latency (per second)", "Speed (per second)" or "GPS track" sheet')
    first = rows[0][0]
    offset = parse_local(first['time_local']) - parse_utc(first['time_utc']).replace(tzinfo=None)
    by_sec = {}
    for r, kind in rows:
        cell = str(r.get('connection') or '').upper() == 'CELLULAR'
        if cell:
            rat = str(r.get('override_network_type') or '')
            tech = str(r.get('data_network_type') or r.get('rat') or 'Cellular')
            if tech.upper() == 'IWLAN':
                tech = str(r.get('rat') or 'Cellular')
            if 'NR' in rat.upper() and 'NR' not in tech.upper():
                tech = f'{tech} ({rat})'
            band = r.get('nr_band') if 'NR' in tech.upper() and r.get('nr_band') else r.get('lte_band')
            cat = f'{tech} band {band}' if band else tech
            sig = num(r.get('nr_ss_rsrp')) if tech.upper().startswith('NR') and num(r.get('nr_ss_rsrp')) is not None else num(r.get('lte_rsrp'))
            sig_name = 'RSRP'
        else:
            ssid = r.get('wifi_ssid')
            cat = f'Wi-Fi {ssid}' if ssid else 'Wi-Fi'
            sig = num(r.get('wifi_rssi'))
            sig_name = 'Wi-Fi RSSI'
        sent, rec = num(r.get('sent')), num(r.get('received'))
        t = parse_local(r['time_local'])
        row = by_sec.setdefault(t, {'t': t, 'rtt': None, 'loss': None, 'mbps': None, 'test': ''})
        row.update({'cat': cat, 'sig': sig, 'sigName': sig_name,
                    'detail': (f"channel {r.get('wifi_channel')}" if not cell and r.get('wifi_channel') else '')})
        if kind == 'lat':
            row['rtt'] = num(r.get('rtt_avg_ms')) if (rec or 0) > 0 else None
            row['loss'] = None if not sent else round(100 * (1 - (rec or 0) / sent))
            if not row['test']:
                row['test'] = str(r.get('test_type') or '')
        elif kind == 'speed':
            row['mbps'] = num(r.get('interval_mbps'))
            row['test'] = str(r.get('test_type') or '')
    secs = [by_sec[k] for k in sorted(by_sec)]
    health = [{'t': parse_local(r['time_local']), 'temp': num(r.get('battery_temp_c')), 'thermal': str(r.get('thermal') or '')}
              for r in sheet('Health') if num(r.get('battery_temp_c')) is not None]
    return {'secs': secs, 'health': health, 'offset': offset}


# ---------------------------------------------------------------- video

def mp4_times(path):
    """(creation time UTC or None, duration s or None) from the mvhd box. Android writes it when recording stops."""
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        chunks = []
        f.seek(max(0, size - 4 * 1024 * 1024))
        chunks.append(f.read())
        f.seek(0)
        chunks.append(f.read(4 * 1024 * 1024))
    for data in chunks:
        i = data.find(b'mvhd')
        if i < 0:
            continue
        ver = data[i + 4]
        try:
            if ver == 1:
                created, _, scale, dur = struct.unpack('>QQIQ', data[i + 8:i + 36])
            else:
                created, _, scale, dur = struct.unpack('>IIII', data[i + 8:i + 24])
        except struct.error:
            continue
        when = None
        if created > 0:
            when = dt.datetime(1904, 1, 1) + dt.timedelta(seconds=created)
            if when.year < 2015:
                when = None
        return when, (dur / scale if scale else None)
    return None, None


def analyze_video(path):
    """-> (frame times s, picture change per frame, duration s). The other person's picture fills the middle of the screen."""
    import cv2
    import numpy as np
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        sys.exit(f'Cannot open {path}')
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    times, diffs, prev, n = [], [], None, 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        t = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0
        h, w = frame.shape[:2]
        # Middle of the screen: clear of the self-view in a corner and the call buttons at the bottom.
        crop = frame[int(h * 0.234):int(h * 0.61), int(w * 0.12):int(w * 0.88)]
        g = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY).astype(np.int16)
        diffs.append(0.0 if prev is None else float(np.abs(g - prev).mean()))
        times.append(t)
        prev = g
        n += 1
        if n % 2000 == 0:
            print(f'    {n}{"/" + str(total) if total else ""} frames', flush=True)
    cap.release()
    if not times:
        sys.exit(f'No frames in {path}')
    return times, diffs, times[-1]


def video_metrics(times, diffs):
    """-> (picture updates per second list, stalls [(start s, length s)])"""
    upd = [t for t, d in zip(times, diffs) if d > UPDATE_DIFF]
    n = int(times[-1]) + 1
    ups = [0] * n
    for t in upd:
        ups[min(n - 1, int(t))] += 1
    stalls = [(round(a, 1), round(b - a, 1)) for a, b in zip(upd, upd[1:]) if b - a >= STALL_S]
    return ups, stalls


# ---------------------------------------------------------------- build

def phone_name(xlsx, summary):
    if summary and os.path.exists(summary):
        for line in open(summary, encoding='utf-8', errors='replace'):
            m = re.match(r'Device:\s+(.+?)(\s{2,}|\(|$)', line)
            if m:
                return m.group(1).strip()
    parts = os.path.basename(xlsx).split('_')
    return ' '.join(parts[1:3]) if len(parts) > 3 else os.path.splitext(os.path.basename(xlsx))[0]


def summary_line(summary, key):
    if summary and os.path.exists(summary):
        for line in open(summary, encoding='utf-8', errors='replace'):
            if line.startswith(key):
                return line[len(key):].strip()
    return None


def build(args):
    phones = []
    for arg in args.runs:
        xlsx, mp4, summary = find_inputs(arg)
        print(f'{os.path.basename(xlsx)}')
        wb = read_workbook(xlsx)
        p = {'name': args.name[len(phones)] if len(args.name) > len(phones) else phone_name(xlsx, summary), 'file': os.path.splitext(os.path.basename(xlsx))[0],
             'weather': summary_line(summary, 'Weather:'), 'wb': wb, 'video': None}
        role = re.search(r'_(?:[A-Za-z0-9]*?)(Base|Mobile|Caller|Callee)_', os.path.basename(xlsx))
        p['role'] = role.group(1) if role else ''
        if mp4:
            print(f'  reading {os.path.basename(mp4)} (this takes a minute or two)')
            times, diffs, dur = analyze_video(mp4)
            ups, stalls = video_metrics(times, diffs)
            created, box_dur = mp4_times(mp4)
            if created:
                start = created - dt.timedelta(seconds=box_dur or dur) + wb['offset']   # file closed at the end
                how = 'file close time minus length'
            else:
                m = re.search(r'ScreenRec_(\d{8})-(\d{6})', os.path.basename(mp4))
                start = dt.datetime.strptime(m.group(1) + m.group(2), '%Y%m%d%H%M%S') if m else wb['secs'][0]['t']
                how = 'file name' if m else 'session start (recording has no time stamp)'
            p['video'] = {'start': start, 'ups': ups, 'stalls': stalls, 'how': how, 'file': os.path.basename(mp4)}
            print(f'  {len(stalls)} stalls of {STALL_S} s or longer; recording starts {start:%H:%M:%S} ({how})')
        else:
            print('  no screen recording found: network lanes only')
        phones.append(p)

    t_min = min([p['wb']['secs'][0]['t'] for p in phones] + [p['video']['start'] for p in phones if p['video']])
    t_max = max(p['wb']['secs'][-1]['t'] for p in phones)
    base = (t_min - dt.timedelta(seconds=10)).replace(microsecond=0)
    base -= dt.timedelta(seconds=base.second % 10)
    rel = lambda t: round((t - base).total_seconds(), 1)
    tmax = int(rel(t_max) + 15)

    cats = []
    for p in phones:
        for s in p['wb']['secs']:
            if s['cat'] not in cats:
                cats.append(s['cat'])
    data = {'base': base.strftime('%Y-%m-%d %H:%M:%S'), 'baseSec': base.hour * 3600 + base.minute * 60 + base.second,
            'tmax': tmax, 'cats': cats, 'stallS': STALL_S, 'phones': []}
    for p in phones:
        secs = p['wb']['secs']
        d = {'name': p['name'], 'role': p['role'], 'file': p['file'], 'weather': p['weather'],
             'sess': [rel(secs[0]['t']), rel(secs[-1]['t']) + 1],
             'sec': [[int(rel(s['t'])), cats.index(s['cat']), s['sig'], s['rtt'], s['loss'], s['sigName'], s['detail'], s['mbps'], s['test']] for s in secs],
             'temp': [[rel(h['t']), h['temp'], h['thermal']] for h in p['wb']['health']],
             'video': None}
        if p['video']:
            v = p['video']
            d['video'] = {'t0': rel(v['start']), 'ups': v['ups'], 'how': v['how'], 'file': v['file'],
                          'stalls': [[round(rel(v['start']) + a, 1), b] for a, b in v['stalls']]}
        data['phones'].append(d)
    data['notes'] = list(args.note)
    return data


def tiles(data):
    out = []
    allst = [(s[1], p['name']) for p in data['phones'] if p['video'] for s in p['video']['stalls']]
    if any(p['video'] for p in data['phones']):
        if allst:
            longest = max(allst)
            out.append((f'{len(allst)} picture stall{"s" if len(allst) != 1 else ""}',
                        f'Gaps of {data["stallS"]} s or more with no picture update. Longest: {longest[0]} s on the {longest[1]} screen.'))
        else:
            out.append(('No picture stalls', f'No gap of {data["stallS"]} s or more without a picture update on either screen.'))
        for p in data['phones']:
            if p['video']:
                n = len(p['video']['stalls'])
                out.append((f'{n} on {p["name"]}', 'Stalls seen on this phone\'s screen (the other phone\'s picture).'))
    for p in data['phones']:
        mb = sorted(s[7] for s in p['sec'] if s[7] is not None)
        if mb:
            out.append((f'{mb[len(mb) // 2]:.0f} Mbps median', f'{p["name"]}: throughput per second, {mb[0]:.0f} to {mb[-1]:.0f} Mbps over {len(mb)} s of test traffic.'))
    for p in data['phones']:
        changes = sum(1 for a, b in zip(p['sec'], p['sec'][1:]) if a[1] != b[1])
        extra = ''
        if p['temp']:
            extra = f' Battery peaked at {max(t[1] for t in p["temp"]):.1f} °C.'
        out.append((f'{changes} network change{"s" if changes != 1 else ""}', f'{p["name"]}.{extra}'))
    return out[:6]


PAGE = r'''<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root{color-scheme:light;--bg:#f6f5f2;--surface:#fcfcfb;--ink:#0b0b0b;--ink2:#52514e;--muted:#8a8882;--grid:#e4e2dc;--line:#3b3a37;--stall:#b3261e;--hatch:#d9d6ce;--tip:#ffffff;__LIGHT__}
@media (prefers-color-scheme:dark){:root{color-scheme:dark;--bg:#121211;--surface:#1a1a19;--ink:#f0efec;--ink2:#c3c2b7;--muted:#8f8d85;--grid:#33322f;--line:#d6d4cc;--stall:#f2857d;--hatch:#3a3936;--tip:#262624;__DARK__}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:1120px;margin:0 auto;padding:28px 20px 60px}h1{font-size:24px;margin:0 0 4px}h2{font-size:17px;margin:34px 0 8px}
.sub{color:var(--ink2);margin:0 0 18px}.find{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:12px;margin:0 0 22px}
.find div{background:var(--surface);border:1px solid var(--grid);border-radius:10px;padding:12px 14px}.find b{display:block;font-size:20px}.find span{color:var(--ink2);font-size:13.5px}
.card{background:var(--surface);border:1px solid var(--grid);border-radius:12px;padding:14px 14px 8px;position:relative}
.legend{display:flex;flex-wrap:wrap;gap:6px 18px;font-size:13px;color:var(--ink2);margin:0 0 6px}.legend i{display:inline-block;width:12px;height:12px;border-radius:3px;vertical-align:-1px;margin-right:6px}
.legend .st{width:3px;height:13px;border-radius:1px;background:var(--stall)}.legend .ha{background:repeating-linear-gradient(135deg,var(--hatch) 0 3px,transparent 3px 6px);border:1px solid var(--hatch)}
.scroll{overflow-x:auto}svg{display:block;min-width:820px;width:100%;height:auto}
svg text{font:11.5px system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;fill:var(--ink2)}svg .ph{font-size:14px;font-weight:650;fill:var(--ink)}svg .role{font-size:12.5px}
svg .lane{fill:var(--ink);font-size:12px;font-weight:600}svg .unit{fill:var(--muted);font-size:11px}svg .seg{fill:#fff;font-size:11.5px;font-weight:600}
#tip{position:absolute;pointer-events:none;background:var(--tip);border:1px solid var(--grid);border-radius:8px;padding:8px 10px;font-size:12.5px;box-shadow:0 4px 16px rgba(0,0,0,.14);display:none;min-width:250px;z-index:5}
#tip table{border-collapse:collapse;margin-top:4px;width:100%}#tip td{padding:1px 0;vertical-align:top}#tip td:first-child{color:var(--ink2);padding-right:10px;white-space:nowrap}#tip .h{font-weight:650;padding-top:6px}
table.t{border-collapse:collapse;width:100%;background:var(--surface);border:1px solid var(--grid);border-radius:10px;font-size:14px}
table.t th,table.t td{text-align:left;padding:7px 12px;border-bottom:1px solid var(--grid);vertical-align:top}table.t th{color:var(--ink2);font-weight:600;font-size:13px}
.num{font-variant-numeric:tabular-nums;white-space:nowrap}.tw{overflow-x:auto}ul{padding-left:20px;margin:6px 0}li{margin:4px 0}.note{color:var(--ink2);font-size:14px}
</style></head><body><main>
<h1>__TITLE__</h1><p class="sub">__SUB__</p>
<div class="find">__TILES__</div>
<div class="card"><div class="legend" id="lg"></div><div class="scroll"><svg id="c" role="img" aria-label="Timeline of network, signal, latency, temperature and picture updates"></svg></div><div id="tip"></div></div>
<div id="stw"><h2>Picture stalls</h2><div class="tw"><table class="t" id="stalls"></table></div></div>
<h2>Network changes</h2><div class="tw"><table class="t" id="net"></table></div>
<h2>How to read this, and its limits</h2>
<ul class="note">
<li class="vid"><b>Picture updates per second</b> counts how often the other person's picture changed on this phone's screen. It is high when the scene moves and low when it is still, so a low value alone does not mean poor quality. A stall is a gap of __STALL__ s or more with no change at all; live video of a still scene still refreshes about once a second.</li>
<li class="vid"><b>Check the stalls against the recording.</b> Leaving the call screen (a small floating window, another app) also shows up as a gap, and so do the first seconds before the call picture settles.</li>
<li><b>Signal</b> is Wi-Fi RSSI while on Wi-Fi and RSRP while on cellular. Both are in dBm but are different measurements: compare within a colour, not across colours.</li>
<li><b>Latency</b> is the per-second average ping round trip; seconds with no reply are left blank, and 10 s or more without any reply is hatched.</li>
<li><b>Timing</b> is good to about one second. __HOW__</li>
<li class="vid"><b>Not measured:</b> sound, picture sharpness, and what the network did between the two phones.</li>
__WEATHER__
</ul>
<script>const DATA=__DATA__;
const NS='http://www.w3.org/2000/svg',W=1060,X0=150,X1=1040,TMAX=DATA.tmax;
const sx=t=>X0+(X1-X0)*t/TMAX,clock=t=>{const s=((DATA.baseSec+Math.round(t))%86400+86400)%86400;return `${Math.floor(s/3600)}:${String(Math.floor(s%3600/60)).padStart(2,'0')}:${String(s%60).padStart(2,'0')}`};
const svg=document.getElementById('c');const el=(n,a,p)=>{const e=document.createElementNS(NS,n);for(const k in a)e.setAttribute(k,a[k]);(p||svg).appendChild(e);return e};
const CV=i=>`var(--c${i%8})`;const short=s=>s.replace(/^Wi-Fi /,'');
document.getElementById('lg').innerHTML=DATA.cats.map((c,i)=>`<span><i style="background:${CV(i)}"></i>${c}</span>`).join('')+(DATA.phones.some(d=>d.video)?'<span><i class="st"></i>Picture stall</span>':'')+(DATA.phones.some(d=>d.sec.some(s=>s[4]===100))?'<span><i class="ha"></i>No ping replies</span>':'');
const defs=el('defs',{});const pat=el('pattern',{id:'h',width:6,height:6,patternUnits:'userSpaceOnUse',patternTransform:'rotate(45)'},defs);el('rect',{width:3,height:6,fill:'var(--hatch)'},pat);
let y=8;const geo=[];
function segs(sec){const o=[];let c=null;for(const s of sec){if(!c||c.c!==s[1]||s[0]>c.b+2){c={c:s[1],a:s[0],b:s[0]+1};o.push(c)}else c.b=s[0]+1}return o}
function axis(y0,h,lo,hi,ticks,fmt){for(const v of ticks){const yy=y0+h-(v-lo)/(hi-lo)*h;el('line',{x1:X0,x2:X1,y1:yy,y2:yy,stroke:'var(--grid)','stroke-width':1});el('text',{x:X0-6,y:yy+4,'text-anchor':'end',class:'unit'}).textContent=fmt(v)}}
function lane(y0,title,unit){el('text',{x:8,y:y0+14,class:'lane'}).textContent=title;if(unit)el('text',{x:8,y:y0+29,class:'unit'}).textContent=unit}
function nice(max,steps){const raw=max/steps,p=Math.pow(10,Math.floor(Math.log10(raw))),m=[1,2,2.5,5,10].find(k=>k*p>=raw)*p;return m}
const H0=64;
DATA.phones.forEach((d,pi)=>{const g={};geo.push(g);
 el('text',{x:8,y:y+16,class:'ph'}).textContent=d.name;el('text',{x:X0,y:y+16,class:'role'}).textContent=(d.role?d.role+'. ':'')+'Session '+clock(d.sess[0])+' to '+clock(d.sess[1])+'. '+d.file;y+=28;
 lane(y,'Network');for(const s of segs(d.sec)){const x=sx(s.a),w=Math.max(2,sx(s.b)-x-2);el('rect',{x,y,width:w,height:22,rx:4,fill:CV(s.c)});const lab=short(DATA.cats[s.c]);if(w>lab.length*7+14)el('text',{x:x+7,y:y+15,class:'seg'}).textContent=lab}
 g.top=y;y+=34;
 // signal
 const sv=d.sec.map(s=>s[2]).filter(v=>v!=null);if(sv.length){const lo=Math.floor(Math.min(...sv,-100)/10)*10,hi=Math.ceil(Math.max(...sv,-30)/10)*10;lane(y,'Signal','RSSI or RSRP');axis(y,H0,lo,hi,[lo,(lo+hi)/2,hi],v=>Math.round(v)+' dBm');
  let run=null,pts='',last=-9;const flush=()=>{if(run!=null&&pts)el('polyline',{points:pts,fill:'none',stroke:CV(run),'stroke-width':2,'stroke-linejoin':'round'});pts=''};
  for(const s of d.sec){if(s[2]==null){flush();run=null;continue}if(run!==s[1]||s[0]>last+2){flush();run=s[1]}last=s[0];pts+=`${sx(s[0]+.5).toFixed(1)},${(y+H0-(s[2]-lo)/(hi-lo)*H0).toFixed(1)} `}flush();y+=H0+30}
 // latency
 const rv=d.sec.map(s=>s[3]).filter(v=>v!=null);if(rv.length||d.sec.some(s=>s[4]===100)){if(!rv.length)rv.push(100);const srt=[...rv].sort((a,b)=>a-b),p98=srt[Math.floor(srt.length*.98)],step=nice(Math.max(50,p98),2),hi=step*2;lane(y,'Latency','ping round trip');axis(y,H0,0,hi,[0,step,hi],v=>v+' ms');
  let pts='',last=-9;const flush=()=>{if(pts)el('polyline',{points:pts,fill:'none',stroke:'var(--line)','stroke-width':1.6,'stroke-linejoin':'round'});pts=''};
  {let a=null,b=null;const box=()=>{if(a!=null&&b-a>=10){el('rect',{x:sx(a),y,width:sx(b+1)-sx(a),height:H0,fill:'url(#h)'});if(sx(b+1)-sx(a)>150)el('text',{x:sx(a)+8,y:y+H0/2+4,class:'unit'}).textContent='No ping replies counted'}a=null};for(const s of d.sec){if(s[4]===100&&(a==null||s[0]<=b+2)){if(a==null)a=s[0];b=s[0]}else if(s[4]===100){box();a=s[0];b=s[0]}else box()}box()}
  for(const s of d.sec){if(s[3]==null||s[0]>last+3){flush()}if(s[3]==null)continue;last=s[0];pts+=`${sx(s[0]+.5).toFixed(1)},${(y+H0-Math.min(hi,s[3])/hi*H0).toFixed(1)} `}flush();y+=H0+30}
 // throughput (data performance tests)
 const mv=d.sec.filter(s=>s[7]!=null);if(mv.length){const srt=mv.map(s=>s[7]).sort((a,b)=>a-b),step=nice(Math.max(1,srt[srt.length-1]),2),hi=step*2;lane(y,'Throughput','test traffic');axis(y,H0,0,hi,[0,step,hi],v=>v+' Mbps');
  let pts='',last=-9,test=null,x0=0;const flush=()=>{if(pts){const xs=pts.trim().split(' ');el('polygon',{points:`${xs[0].split(',')[0]},${y+H0} ${pts}${xs[xs.length-1].split(',')[0]},${y+H0}`,fill:'var(--line)','fill-opacity':.12});el('polyline',{points:pts,fill:'none',stroke:'var(--line)','stroke-width':1.6,'stroke-linejoin':'round'});if(test&&sx(last)-x0>test.length*6)el('text',{x:x0+3,y:y-3,class:'unit'}).textContent=test}pts=''};
  for(const s of mv){if(s[0]>last+2||s[8]!==test){flush();test=s[8];x0=sx(s[0])}last=s[0];pts+=`${sx(s[0]+.5).toFixed(1)},${(y+H0-Math.min(hi,s[7])/hi*H0).toFixed(1)} `}flush();y+=H0+30}
 // temperature
 if(d.temp.length>1){const tv=d.temp.map(t=>t[1]),lo=Math.floor(Math.min(...tv)/5)*5,hi=Math.max(lo+10,Math.ceil(Math.max(...tv)/5)*5);lane(y,'Battery temp','from the phone');axis(y,46,lo,hi,[lo,hi],v=>v+' °C');
  el('polyline',{points:d.temp.map(t=>`${sx(t[0]).toFixed(1)},${(y+46-(t[1]-lo)/(hi-lo)*46).toFixed(1)}`).join(' '),fill:'none',stroke:'var(--line)','stroke-width':1.6});y+=46+30}
 // video
 if(d.video){const v=d.video;lane(y,'Picture updates','per second, 0 to 30');axis(y,H0,0,30,[0,15,30],v=>v+' /s');
  let p=`${sx(v.t0).toFixed(1)},${y+H0} `;v.ups.forEach((u,i)=>{p+=`${sx(v.t0+i+.5).toFixed(1)},${(y+H0-Math.min(30,u)/30*H0).toFixed(1)} `});p+=`${sx(v.t0+v.ups.length).toFixed(1)},${y+H0}`;
  el('polygon',{points:p,fill:'var(--line)','fill-opacity':.16,stroke:'var(--line)','stroke-width':1.4,'stroke-linejoin':'round'});
  for(const s of v.stalls){const x=sx(s[0]);el('rect',{x,y:y-4,width:Math.max(3,sx(s[0]+s[1])-x),height:H0+4,rx:1.5,fill:'var(--stall)','fill-opacity':.9})}y+=H0+30}
 for(const s of segs(d.sec).slice(1))el('line',{x1:sx(s.a),x2:sx(s.a),y1:g.top+24,y2:y-30,stroke:'var(--muted)','stroke-width':1,'stroke-dasharray':'3 3'});
 y+=6;});
const ay=y-10,span=TMAX,stepT=[10,15,30,60,120,300,600,900,1800,3600].find(s=>span/s<=11)||7200;
for(let t=Math.ceil(DATA.baseSec/stepT)*stepT-DATA.baseSec;t<=TMAX;t+=stepT){el('line',{x1:sx(t),x2:sx(t),y1:ay,y2:ay+5,stroke:'var(--muted)'});el('text',{x:sx(t),y:ay+19,'text-anchor':'middle'}).textContent=stepT<60?clock(t):clock(t).slice(0,-3)}
el('line',{x1:X0,x2:X1,y1:ay,y2:ay,stroke:'var(--muted)'});el('text',{x:8,y:ay+19,class:'unit'}).textContent='Phone clock';const H=ay+28;svg.setAttribute('viewBox',`0 0 ${W} ${H}`);
const cross=el('line',{y1:30,y2:ay,stroke:'var(--ink)','stroke-width':1,opacity:0});const hit=el('rect',{x:X0,y:0,width:X1-X0,height:H,fill:'transparent'});const tip=document.getElementById('tip');
function at(d,t){const s=d.sec.find(r=>r[0]===Math.floor(t));let r=`<tr><td colspan=2 class=h>${d.name}</td></tr>`;if(!s)return r+'<tr><td colspan=2>Session not running</td></tr>';
 r+=`<tr><td>Network</td><td>${DATA.cats[s[1]]}${s[6]?', '+s[6]:''}</td></tr><tr><td>${s[5]}</td><td>${s[2]==null?'not reported':s[2]+' dBm'}</td></tr>`;
 if(s[7]!=null)r+=`<tr><td>Throughput</td><td>${s[7].toFixed(1)} Mbps${s[8]?' ('+s[8]+')':''}</td></tr>`;
 if(s[3]!=null||s[4]!=null)r+=`<tr><td>Latency</td><td>${s[3]==null?'no reply this second':Math.round(s[3])+' ms'}${s[4]?' ('+s[4]+'% lost)':''}</td></tr>`;
 if(d.temp.length){const h=d.temp.reduce((a,b)=>Math.abs(b[0]-t)<Math.abs(a[0]-t)?b:a);r+=`<tr><td>Battery</td><td>${h[1]} °C${h[2]&&h[2]!=='None'?', thermal '+h[2]:''}</td></tr>`}
 if(d.video){const v=d.video,i=Math.floor(t-v.t0),st=v.stalls.find(q=>t>=q[0]&&t<=q[0]+q[1]);r+=`<tr><td>Picture</td><td>${i<0||i>=v.ups.length?'not recorded':v.ups[i]+' updates/s'}${st?' <b>(stall '+st[1]+' s)</b>':''}</td></tr>`}return r}
function move(ev){const b=svg.getBoundingClientRect();const x=(ev.clientX-b.left)/b.width*W;const t=Math.max(0,Math.min(TMAX-1,(x-X0)/(X1-X0)*TMAX));cross.setAttribute('x1',sx(t));cross.setAttribute('x2',sx(t));cross.setAttribute('opacity',.55);
 tip.innerHTML=`<b>${clock(t)}</b><table>${DATA.phones.map(d=>at(d,t)).join('')}</table>`;tip.style.display='block';const c=svg.closest('.card').getBoundingClientRect();let lx=ev.clientX-c.left+16;if(lx+280>c.width)lx=ev.clientX-c.left-290;tip.style.left=Math.max(4,lx)+'px';tip.style.top=Math.max(4,ev.clientY-c.top-40)+'px'}
hit.addEventListener('pointermove',move);hit.addEventListener('pointerdown',move);hit.addEventListener('pointerleave',()=>{tip.style.display='none';cross.setAttribute('opacity',0)});
const netAt=(d,t)=>{const s=d.sec.find(r=>r[0]===Math.floor(t));return s?DATA.cats[s[1]]:'-'};
const all=[];DATA.phones.forEach((d,i)=>{if(d.video)for(const s of d.video.stalls)all.push({i,t:s[0],d:s[1]})});all.sort((a,b)=>a.t-b.t);
let rows='<tr><th>Time</th><th>Screen</th><th>Length</th><th>That phone was on</th>'+(DATA.phones.length>1?'<th>Other phone was on</th>':'')+'</tr>';
for(const s of all){const o=DATA.phones[s.i===0?1:0];rows+=`<tr><td class=num>${clock(s.t)}</td><td>${DATA.phones[s.i].name}</td><td class=num>${s.d.toFixed(1)} s</td><td>${netAt(DATA.phones[s.i],s.t)}</td>${o?'<td>'+netAt(o,s.t)+'</td>':''}</tr>`}
if(!DATA.phones.some(d=>d.video)){document.getElementById('stw').style.display='none';document.querySelectorAll('.vid').forEach(e=>e.style.display='none')}document.getElementById('stalls').innerHTML=all.length?rows:'<tr><td>None of '+DATA.stallS+' s or longer'+(DATA.phones.some(d=>d.video)?'':' (no screen recording was given)')+'.</td></tr>';
rows='<tr><th>Time</th><th>Phone</th><th>Change</th></tr>';const ne=[];DATA.phones.forEach(d=>{let prev=null;for(const s of segs(d.sec)){if(prev&&prev.c!==s.c)ne.push({t:s.a,n:d.name,txt:`${DATA.cats[prev.c]} to ${DATA.cats[s.c]}`});prev=s}});ne.sort((a,b)=>a.t-b.t);
for(const e of ne)rows+=`<tr><td class=num>${clock(e.t)}</td><td>${e.n}</td><td>${e.txt}</td></tr>`;document.getElementById('net').innerHTML=ne.length?rows:'<tr><td>No network changes.</td></tr>';
</script></main></body></html>
'''


def render(data):
    names = ' and '.join(p['name'] for p in data['phones'])
    title = f'{"Video call" if any(p["video"] for p in data["phones"]) else "Test"} timeline: {names}'
    day = dt.datetime.strptime(data['base'], '%Y-%m-%d %H:%M:%S')
    sub = f'{day:%B} {day.day}, {day.year}, phone clock. Network, signal, latency, throughput and, where a screen recording was given, picture behaviour, on one clock.'
    til = ''.join(f'<div><b>{html.escape(a)}</b><span>{html.escape(b)}</span></div>' for a, b in tiles(data))
    how = ' '.join(f'{html.escape(p["name"])}: recording placed by {p["video"]["how"]}.' for p in data['phones'] if p['video'])
    notes = ''.join(f'<li>{html.escape(n)}</li>' for n in data.get('notes', []))
    weather = notes + ''.join(f'<li><b>Weather, {html.escape(p["name"])}:</b> {html.escape(p["weather"])}</li>' for p in data['phones'] if p['weather'])
    page = PAGE
    for k, v in (('__TITLE__', html.escape(title)), ('__SUB__', html.escape(sub)), ('__TILES__', til), ('__STALL__', str(data['stallS'])),
                 ('__HOW__', how), ('__WEATHER__', weather),
                 ('__LIGHT__', ';'.join(f'--c{i}:{c}' for i, c in enumerate(PALETTE_LIGHT))),
                 ('__DARK__', ';'.join(f'--c{i}:{c}' for i, c in enumerate(PALETTE_DARK))),
                 ('__DATA__', json.dumps(data, separators=(',', ':')).replace('</', '<\\/'))):
        page = page.replace(k, v)
    return page


def main():
    ap = argparse.ArgumentParser(description='Video call timeline (HTML) from one or two run folders.')
    ap.add_argument('runs', nargs='+', help='run folder, or "workbook.xlsx,recording.mp4"')
    ap.add_argument('-o', '--out', help='output .html (default: next to the first workbook)')
    ap.add_argument('--name', action='append', default=[], help='display name for a phone, in the order of the runs (repeat per phone)')
    ap.add_argument('--note', action='append', default=[], help='extra line for the notes at the bottom (repeatable)')
    args = ap.parse_args()
    data = build(args)
    out = args.out
    if not out:
        first, _, _ = find_inputs(args.runs[0])
        out = os.path.join(os.path.dirname(os.path.abspath(first)), data['phones'][0]['file'] + '_timeline.html')
    with open(out, 'w', encoding='utf-8') as f:
        f.write(render(data))
    print(f'Wrote {out}')


if __name__ == '__main__':
    main()
