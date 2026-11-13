import numpy as np, cv2, json
from PIL import Image
D=json.load(open('circles.json'))
res={}
for key,v in D.items():
    im=np.asarray(Image.open(v['file']).convert('RGBA'))
    rgb=im[...,:3].astype(np.float32)*(im[...,3:4]/255.0)
    g=cv2.cvtColor(rgb.astype(np.uint8),cv2.COLOR_RGB2GRAY)
    g=cv2.GaussianBlur(g,(5,5),1.5)
    rs=sorted(c[2] for c in v['circles']); rm=rs[len(rs)//2]
    cs=cv2.HoughCircles(g,cv2.HOUGH_GRADIENT,dp=1,minDist=rm*1.5,param1=80,param2=30,minRadius=int(rm*.88),maxRadius=int(rm*1.12))
    cs=[] if cs is None else cs[0].tolist()
    exp=20 if key=='M' else 9
    cs=sorted(cs,key=lambda c:-c[2])  # keep
    # accumulator order = strength; take first exp
    cs=cs
    res[key]={'n':len(cs),'circles':cs[:40]}
    print(key,'rm',round(rm),'found',len(cs))
json.dump(res,open('hough.json','w'))
