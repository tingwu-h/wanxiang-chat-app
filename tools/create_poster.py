"""Render evergreen Wanxiang posters from the original logo; no image API."""
from pathlib import Path
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/posters'
OUT.mkdir(parents=True, exist_ok=True)
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
URL = 'github.com/tingwu-h/wanxiang-chat-app'
WHITE, MUTED, CYAN = '#F1F6FF', '#A5B8D4', '#73E7F2'
logo = Image.open(ROOT / 'android/app/src/main/res/drawable-nodpi/wanxiang_splash_android12.png').convert('RGBA')
logo = logo.crop(logo.getbbox())
def text(im,x,y,value,size,color=WHITE,bold=False,anchor='lt'):
    f=ImageFont.truetype(BOLD if bold else FONT,size)
    d=ImageDraw.Draw(im)
    b=d.textbbox((x,y),value,font=f,anchor=anchor)
    assert b[0]>=0 and b[2]<=im.width and b[1]>=0 and b[3]<=im.height,(value,b)
    d.text((x,y),value,font=f,fill=color,anchor=anchor)
def background(w,h):
    y,x=np.mgrid[0:h,0:w].astype(float)
    # Broad, low-contrast light fields keep the color transition calm and print-friendly.
    glow=np.exp(-(((x-w*.82)/(w*.72))**2+((y-h*.48)/(h*.68))**2)*1.15)
    violet=np.exp(-(((x-w*.1)/(w*.85))**2+((y-h*.85)/(h*.72))**2)*1.1)
    arr=np.zeros((h,w,3))+[8,14,34]
    arr+=glow[...,None]*[7,22,38]+violet[...,None]*[8,3,18]
    return Image.fromarray(arr.astype('uint8')).convert('RGBA')
def paste_logo(im,x,y,size):
    scaled=logo.resize((size,size),Image.Resampling.LANCZOS)
    mask=Image.new('L',(size,size))
    ImageDraw.Draw(mask).rounded_rectangle((2,2,size-3,size-3),radius=size*.255,fill=255)
    scaled.putalpha(Image.fromarray(np.minimum(np.array(scaled.getchannel('A')),np.array(mask))))
    im.alpha_composite(scaled,(x,y))
def orbit(im,cx,cy,rx,ry,angle):
    layer=Image.new('RGBA',im.size)
    d=ImageDraw.Draw(layer)
    a=math.radians(angle)
    points=[]
    for t in np.linspace(0,2*math.pi,500):
        u,v=rx*math.cos(t),ry*math.sin(t)
        points.append((cx+u*math.cos(a)-v*math.sin(a),cy+u*math.sin(a)+v*math.cos(a)))
    d.line(points,fill=(94,177,222,28),width=2)
    for i,c in [(55,(87,225,239,150)),(285,(157,119,253,135))]:
        x,y=points[i]
        d.ellipse((x-6,y-6,x+6,y+6),fill=c)
    im.alpha_composite(layer)
def header(im,x,y):
    paste_logo(im,x,y,68)
    text(im,x+91,y+2,'万象',38,bold=True)
    text(im,x+91,y+48,'WANXIANG',15,MUTED)
def feature(im,x,y,number,title,detail):
    text(im,x,y,number,19,CYAN)
    text(im,x,y+42,title,32,bold=True)
    text(im,x,y+98,detail,23,MUTED)
def save(im,name):
    rgb=im.convert('RGB')
    rgb.save(OUT/f'{name}.png',optimize=True,dpi=(300,300))
    rgb.save(OUT/f'{name}.jpg',quality=94,subsampling=0,dpi=(300,300))
    p=rgb.copy(); p.thumbnail((1000,1400))
    p.save(OUT/f'{name}-preview.jpg',quality=90)
def portrait():
    im=background(1440,1920)
    header(im,110,100)
    text(im,1330,126,'你的 AI 对话空间',24,MUTED,anchor='rt')
    text(im,104,274,'万象聚合',120,bold=True)
    text(im,104,431,'模型无界',120,CYAN,bold=True)
    text(im,110,615,'让每个想法，都有回响。',37)
    text(im,110,684,'把常用的 AI 放在一起，让对话更自在。',27,MUTED)
    orbit(im,740,1095,536,227,-19)
    orbit(im,740,1095,478,278,24)
    paste_logo(im,486,845,468)
    text(im,132,955,'灵感，从一句话开始',23,MUTED)
    text(im,1302,1253,'换个模型，多一种思路',23,MUTED,anchor='rt')
    d=ImageDraw.Draw(im)
    d.line((110,1420,1330,1420),fill='#2B3D58',width=2)
    feature(im,110,1464,'01','随心选择','找到适合当下的模型')
    feature(im,543,1464,'02','不止文字','带上图片，聊得更明白')
    feature(im,976,1464,'03','接着聊下去','留住对话，也留住思路')
    d.line((110,1674,1330,1674),fill='#2B3D58',width=2)
    text(im,110,1716,'从一个问题开始。',37,bold=True)
    text(im,110,1775,URL,24,MUTED)
    text(im,110,1826,'Android · 使用你自己的 API Key',21,MUTED)
    d.rectangle((1162,1714,1329,1881),fill='#FFFFFF')
    save(im,'wanxiang-poster-portrait')
def landscape():
    im=background(1920,1080)
    header(im,110,84)
    text(im,1810,110,'你的 AI 对话空间',23,MUTED,anchor='rt')
    text(im,103,250,'万象聚合',99,bold=True)
    text(im,103,381,'模型无界',99,CYAN,bold=True)
    text(im,110,546,'让每个想法，都有回响。',33)
    text(im,110,605,'把常用的 AI 放在一起，让对话更自在。',25,MUTED)
    orbit(im,1405,465,402,178,-22)
    orbit(im,1405,465,366,216,24)
    paste_logo(im,1210,270,390)
    text(im,1405,729,'不同的模型，同样自在的对话。',23,MUTED,anchor='mt')
    d=ImageDraw.Draw(im)
    d.line((110,800,1810,800),fill='#2B3D58',width=2)
    feature(im,110,839,'01','随心选择','找到适合当下的模型')
    feature(im,515,839,'02','不止文字','带上图片，聊得更明白')
    feature(im,920,839,'03','接着聊下去','留住对话，也留住思路')
    text(im,1350,860,'从一个问题开始。',28,bold=True)
    text(im,1350,920,'Android',21,CYAN)
    text(im,1350,957,'使用你自己的 API Key',19,MUTED)
    d.rectangle((1662,839,1809,986),fill='#FFFFFF')
    text(im,110,1016,URL,19,MUTED)
    save(im,'wanxiang-poster-landscape')
portrait()
landscape()
print('Saved posters to',OUT)
