import numpy as np, cv2, glob, json, sys
from PIL import Image
fs=sorted(glob.glob('/workspace/files/uploads/*.webp'))
use={'A':14,'B':1,'C':8,'D':15,'E':18,'F':11,'G':6,'H':17,'I':10,'J':12,'K':13,'L':16,'M':19}
out={}
for key,i in use.items():
    im=Image.open(fs[i]).convert('RGBA'); a=np.asarray(im)
    fg=((a[...,:3].max(-1)>22)&(a[...,3]>40)).astype(np.uint8)
    fg=cv2.morphologyEx(fg,cv2.MORPH_CLOSE,np.ones((9,9),np.uint8))
    # fill holes
    cnts,_=cv2.findContours(fg,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    filled=np.zeros_like(fg); cv2.drawContours(filled,cnts,-1,1,-1)
    # distance transform peaks give centres + radii robustly even if discs touch
    dt=cv2.distanceTransform(filled,cv2.DIST_L2,5)
    circles=[]
    d=dt.copy()
    H,W=d.shape
    while True:
        y,x=np.unravel_index(d.argmax(),d.shape); r=d[y,x]
        if circles and r<0.6*min(c[2] for c in circles): break
        if r<20: break
        circles.append((int(x),int(y),float(r)))
        cv2.circle(d,(int(x),int(y)),int(r*1.6),0,-1)
    circles.sort(key=lambda c:(round(c[1]/(c[2]*1.2)),c[0]))
    out[key]={'i':i,'file':fs[i],'size':im.size,'circles':circles}
    print(key,i,len(circles),[ (c[0],c[1],round(c[2])) for c in circles])
json.dump(out,open('circles.json','w'),indent=1)
