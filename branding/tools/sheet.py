import os,sys,re
B=sys.argv[1]
def svg(c,v,w):
    s=open(f"{B}/{c}/distribution/pactfall-{c}-{v}.svg").read()
    s=re.sub(r'<\?xml[^>]*>','',s)
    vw,vh=map(float,re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"',s).groups())
    return re.sub(r'width="[\d.]+" height="[\d.]+"',f'width="{w}" height="{w*vh/vw:.1f}"',s,1)
rows=[("seal-forum","2b · Broken seal with stele lettering (your pick)"),("stele","1 · Carved stele"),("seal","2 · Broken seal"),("manuscript-camel","3 · Manuscript colophon, PactFall"),("manuscript","3b · Manuscript colophon, Pactfall")]
h=['<!doctype html><meta charset="utf-8"><title>Pactfall title concepts</title><style>body{margin:0;font:600 22px/1.4 system-ui,sans-serif;color:#211d18;background:#fff}.row{display:grid;grid-template-columns:1fr 1fr;}.cell{padding:36px 40px;display:flex;flex-direction:column;gap:26px;align-items:flex-start}.l{background:#efe8da}.d{background:#15181b;color:#ece4d3}.small{display:flex;gap:34px;align-items:center;flex-wrap:wrap}h2{margin:0;font-size:26px}.cap{font:500 16px system-ui;opacity:.75}.mono{background:#fff}.monod{background:#000;color:#fff}</style>']
for c,t in rows:
    h.append(f'<div class="row"><div class="cell l"><h2>{t} · on light</h2>{svg(c,"on-light",760)}<div class="small">{svg(c,"on-light",240)}{svg(c,"on-light",120)}{svg(c,"on-light",80)}</div><div class="cap">760, 240, 120 and 80 px wide</div></div>'
             f'<div class="cell d"><h2>{t} · on dark</h2>{svg(c,"on-dark",760)}<div class="small">{svg(c,"on-dark",240)}{svg(c,"on-dark",120)}{svg(c,"on-dark",80)}</div><div class="cap">760, 240, 120 and 80 px wide</div></div></div>')
    h.append(f'<div class="row"><div class="cell mono"><div class="small">{svg(c,"mono-black",360)}<span class="cap">mono black</span></div></div><div class="cell monod"><div class="small">{svg(c,"mono-white",360)}<span class="cap">mono white</span></div></div></div>')
h.append(f'<div class="row"><div class="cell l"><h2>Seal mark alone</h2><div class="small">{svg("seal-mark","on-light",128)}{svg("seal-mark","on-light",64)}{svg("seal-mark","on-light",32)}{svg("seal-mark","on-light",16)}<span class="cap">128, 64, 32, 16 px</span></div></div><div class="cell d"><h2>&nbsp;</h2><div class="small">{svg("seal-mark","on-dark",128)}{svg("seal-mark","on-dark",64)}{svg("seal-mark","on-dark",32)}{svg("seal-mark","on-dark",16)}<span class="cap">128, 64, 32, 16 px</span></div></div></div>')
os.makedirs(f"{B}/sheet",exist_ok=True)
open(f"{B}/sheet/pactfall-comparison-sheet.html","w").write("\n".join(h))
