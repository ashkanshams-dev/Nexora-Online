import numpy as np, cv2, json, os
from PIL import Image, ImageDraw
D=json.load(open('circles.json')); Hh=json.load(open('hough.json'))
final={}
for key,v in D.items():
    exp=20 if key=='M' else 9
    cs=Hh[key]['circles']; rs=sorted(c[2] for c in cs); rm=np.median([c[2] for c in cs])
    keep=[]
    for c in sorted(cs,key=lambda c:abs(c[2]-rm)):
        if all(np.hypot(c[0]-k[0],c[1]-k[1])>rm*1.3 for k in keep): keep.append(c)
    keep=keep[:exp]
    assert len(keep)==exp,(key,len(keep))
    rowh=rm*2*1.0
    ys=sorted(k[1] for k in keep)
    keep.sort(key=lambda c:(int((c[1]-ys[0]+rm)/(rowh*1.05)),c[0]))
    final[key]=keep
    im=Image.open(v['file']).convert('RGB'); d=ImageDraw.Draw(im)
    for j,(x,y,r) in enumerate(keep):
        d.ellipse([x-r,y-r,x+r,y+r],outline=(255,0,0),width=3); d.text((x,y),str(j),fill=(0,255,0))
    im.thumbnail((600,600)); im.save(f'chk_{key}.png')
json.dump(final,open('final.json','w'))
print({k:len(v) for k,v in final.items()})
