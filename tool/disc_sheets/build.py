import numpy as np, json, os, re
from PIL import Image
from names import NAMES
D=json.load(open('circles.json')); FN=json.load(open('final.json'))
REPO='/workspace/work/Nexora-Online'; OUT='/tmp/v11'
LEAGUE={
 'epl':['Manchester City','Liverpool','Arsenal','Tottenham','Newcastle United','Aston Villa','West Ham United','Everton','Manchester United','Chelsea'],
 'laliga':['Real Madrid','Barcelona','Atletico Madrid','Sevilla','Valencia','Villarreal'],
 'seriea':['Juventus','AC Milan','Inter Milan','Napoli','Lazio','Fiorentina'],
 'bund':['Bayern Munich','Borussia Dortmund','Bayer Leverkusen','RB Leipzig','Wolfsburg'],
 'ligue':['Marseille','Lyon'],
 'euro':['Ajax','Celtic','Sporting CP','Shakhtar Donetsk','Galatasaray','Fenerbahce'],
 'asia':['Persepolis','Esteghlal','Al Nassr','Al Hilal'],
 'amer':['Flamengo','Corinthians','River Plate','Inter Miami'],
}
CATLABEL={'epl':'Premier League','laliga':'La Liga','seriea':'Serie A','bund':'Bundesliga','ligue':'Ligue 1','euro':'Europe · Other Leagues','asia':'Asia · Iran & Saudi','amer':'Americas','natv':'National Teams','flag':'Flags','carv':'Cars'}
def cat_of(sheet,name):
    if sheet=='B': return 'carv'
    if sheet in 'GIL': return 'natv'
    if sheet in 'HK': return 'flag'
    for k,v in LEAGUE.items():
        if name in v: return k
    raise Exception(name)
# existing names (for "II" suffixes)
existing=set()
for l in open(f'{REPO}/supabase/discs_v10.sql'):
    m=re.match(r"\('(\w+)','(\w+)','(.*?)',",l)
    if m: existing.add(m.group(3).replace("''","'"))
CAR_STATS={'Mercedes-Benz':(6,5),'BMW':(5,7),'Toyota':(6,6),'Ferrari':(7,5),'Lamborghini':(7,5),'Porsche':(6,5),'Tesla':(6,6),'Audi':(6,6),'Ford':(5,6)}
order='ABCDEFJ' + 'GIL' + 'HK' + ''  # clubs first, then nations, flags; B handled in its own cat
counts={}; used=set(existing); rows=[]; skipped=[]
def unique(n):
    if n not in used: used.add(n); return n
    for s in ['II','III','IV','V','VI']:
        c=f'{n} {s}'
        if c not in used: used.add(c); return c
def mask_crop(im,x,y,r):
    S=4; R=int(round(r)); size=2*R
    box=(int(round(x))-R,int(round(y))-R,int(round(x))+R,int(round(y))+R)
    c=im.crop(box)  # original pixels
    yy,xx=np.mgrid[:size*S,:size*S]
    m=(((xx+.5)/S-R)**2+((yy+.5)/S-R)**2)<=(R-1.5)**2
    m=m.reshape(size,S,size,S).mean((1,3))
    a=np.asarray(c).copy().astype(np.float32)
    a[...,3]=a[...,3]*m
    out=Image.fromarray(a.round().astype(np.uint8),'RGBA')
    if size>384: out=out.resize((384,384),Image.LANCZOS)
    return out
for sheet in 'ABCDEFJGILHKBM':
    pass
seq=[s for s in 'ACDEFJ']+['B']+[s for s in 'GIL']+[s for s in 'HK']
for sheet in seq+['M']:
    if sheet=='M':
        for n in NAMES['M']: skipped.append((n,'identical art to existing car disc (car14–car33, the "II"/v10 car set)'))
        continue
    src=Image.open(D[sheet]['file']).convert('RGBA')
    for j,(x,y,r) in enumerate(FN[sheet]):
        base=NAMES[sheet][j]; cat=cat_of(sheet,base)
        idx=counts.get(cat,0); counts[cat]=idx+1
        name=unique(base)
        key=f'{cat}{idx:02d}'; did=f'{cat}{idx}'
        os.makedirs(f'{OUT}/assets/g/teams_v11/{cat}',exist_ok=True)
        path=f'assets/g/teams_v11/{cat}/{key}.webp'
        mask_crop(src,x,y,r).save(f'{OUT}/{path}','WEBP',quality=90,method=4)
        pw,ac=CAR_STATS.get(base,(5,5)) if cat=='carv' else (5,5)
        price=130 if cat=='carv' else 0
        rows.append(dict(id=did,key=key,cat=cat,name=name,price=price,power=pw,acc=ac,path=path,sheet=sheet,src=os.path.basename(D[sheet]['file'])))
json.dump({'rows':rows,'skipped':skipped,'cats':CATLABEL},open('v11.json','w'),indent=1,ensure_ascii=False)
print(len(rows),'new;',len(skipped),'skipped'); print(counts)
