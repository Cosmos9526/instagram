"""Render original design guides and video storyboards, not AI model output."""
from pathlib import Path
import math, random, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.prompt_styles import prompt_styles
OUT = Path(__file__).resolve().parents[1] / 'app/previews/styles'
OUT.mkdir(parents=True, exist_ok=True)
W,H=640,440
FONT='/System/Library/Fonts/Supplemental/Arial.ttf'
if not Path(FONT).exists(): FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
def font(n): return ImageFont.truetype(FONT,n)
ORANGE='#ff7900'; INK='#172333'; CREAM='#fff7ed'

def phone(d,x,y,scale=1,color=ORANGE,screen='#fff7ed',angle=False):
    w,h=int(106*scale),int(150*scale)
    d.rounded_rectangle((x,y,x+w,y+h),radius=int(15*scale),fill=color)
    d.rounded_rectangle((x+8*scale,y+12*scale,x+w-8*scale,y+h-12*scale),radius=9*scale,fill=screen)
    d.ellipse((x+w*.36,y+h*.30,x+w*.64,y+h*.5),fill=color)
    for k in range(3): d.rounded_rectangle((x+23*scale,y+h*.6+k*10*scale,x+w-23*scale,y+h*.63+k*10*scale),radius=2,fill=color)

def person(d,x,y,woman=False,color=INK):
    d.ellipse((x-16,y,x+16,y+32),fill='#d9ac87')
    if woman:d.pieslice((x-23,y-7,x+23,y+40),180,355,fill=color)
    else:d.pieslice((x-17,y-3,x+17,y+18),180,355,fill=color)
    d.rounded_rectangle((x-28,y+37,x+28,y+113),radius=18,fill=color)

def frame_scene(name,beat):
    im=Image.new('RGB',(186,268),'#faf6ef');d=ImageDraw.Draw(im)
    d.rectangle((0,210,186,268),fill='#ece4d7')
    if name in ('ugc_testimonial','founder_story','day_in_life','news_explainer','myth_vs_fact'):
        person(d,80+beat*8,75,name=='ugc_testimonial',ORANGE if beat==2 else INK)
        if name=='news_explainer':
            d.rounded_rectangle((14,12,172,55),radius=6,fill=INK);d.text((24,24),'AI UPDATE',font=font(16),fill='white')
        if name=='myth_vs_fact':d.text((20,15),['MYTH','CHECK','FACT'][beat],font=font(22),fill=INK)
        if name=='founder_story': d.ellipse((20,20,155,210),outline='#eac28f',width=3)
        if name=='day_in_life':d.text((15,20),['START','CREATE','DELIVER'][beat],font=font(16),fill=INK)
        phone(d,120,150,.36)
    elif name=='before_after':
        if beat==0:
            for i in range(7):d.line((20,70+i*15,150-i*7,50+i*20),fill='#b4ada5',width=4)
        else: phone(d,52,50,1,ORANGE if beat==2 else '#bcb2a1')
        d.text((16,16),['BEFORE','CHANGE','AFTER'][beat],font=font(17),fill=INK)
    elif name in ('tutorial_steps','unboxing','stop_motion'):
        if name=='unboxing' and beat==0:d.rectangle((36,83,152,200),fill='#dba677');d.line((94,83,94,200),fill='#b87a43',width=9)
        else:
            phone(d,56,72,.8)
            if name=='tutorial_steps':d.ellipse((18,17,53,52),fill=ORANGE);d.text((29,24),str(beat+1),font=font(18),fill='white')
            if name=='stop_motion':
                for j in range(4):d.ellipse((15+j*41,30+beat*12,30+j*41,45+beat*12),fill=ORANGE)
    elif name=='problem_solution':
        person(d,50,88,color=INK if beat==0 else ORANGE)
        d.text((115,42),['?','!','✓'][beat],font=font(40),fill=INK)
        if beat>0:phone(d,105,110,.6)
    elif name=='pov':
        d.polygon([(0,250),(40,160),(75,173),(55,268)],fill='#d9ac87');phone(d,59,52,.9)
    elif name=='asmr_detail':
        for j in range(7):d.arc((12+j*8,20+j*8,240+j*8,250+j*8),30,290,fill='#dca253',width=4)
        phone(d,20-beat*12,72-beat*15,1.6)
    elif name=='trend_hook':
        for j in range(8):d.line((93,130,93+int(180*math.cos(j*math.pi/4)),130+int(180*math.sin(j*math.pi/4))),fill='#ffb667',width=4)
        phone(d,40,60,1)
    else:
        im=Image.new('RGB',(186,268),INK);d=ImageDraw.Draw(im)
        d.ellipse((15,185,180,233),fill='#2c3b4c');phone(d,40-beat*7,43+beat*9,1.05,ORANGE,'#263343')
        d.line((20+beat*15,15,155,60),fill='#f5c087',width=3)
    return im

for s in prompt_styles():
    key=s['id'].split('_',1)[1]
    im=Image.new('RGB',(W,H),CREAM);d=ImageDraw.Draw(im)
    if s['kind']=='video':
        d.text((22,16),s['name_en'],font=font(24),fill=INK)
        for i in range(3):
            x=22+i*204;im.paste(frame_scene(key,i),(x,57));d=ImageDraw.Draw(im)
            d.text((x+46,336),['0–2s','2–5s','5–8s'][i],font=font(18),fill=INK)
        d.rounded_rectangle((22,375,618,424),radius=10,fill=INK)
        d.text((42,388),'8–10s  ·  ORIGINAL LOGO END CARD',font=font(19),fill='white')
    else:
        if key=='neon':
            im=Image.new('RGB',(W,H),'#0d1724');d=ImageDraw.Draw(im)
            for i in range(12):d.line((i*64,0,320+i*25,440),fill='#154048',width=2)
            for i in range(8):d.ellipse((230-i*7,65-i*7,418+i*7,335+i*7),outline='#17686b',width=2)
            phone(d,262,92,1.45,'#14b8ba','#112631')
        elif key=='isometric':
            d.polygon([(95,270),(330,360),(552,247),(317,157)],fill='#efcba3')
            d.polygon([(95,270),(95,296),(330,386),(330,360)],fill='#be8a55')
            d.polygon([(330,360),(552,247),(552,273),(330,386)],fill='#d49c64')
            d.polygon([(238,90),(371,132),(371,290),(238,246)],fill=INK)
            d.polygon([(250,108),(358,140),(358,270),(250,237)],fill=ORANGE)
            for x,y in [(145,215),(448,220)]:d.ellipse((x,y,x+50,y+20),fill='#c3955b');d.rectangle((x,y-45,x+50,y+10),fill='#fbab54');d.ellipse((x,y-55,x+50,y-35),fill='#ffce91')
        elif key=='paper':
            for i,c in enumerate(['#eecba4','#f7ad63','#ff7900','#ffe1bd']):
                d.rounded_rectangle((70+i*36,50+i*28,570-i*22,390-i*8),radius=50,fill=c)
            phone(d,259,108,1.4,INK)
        elif key=='clay':
            d.ellipse((120,277,525,365),fill='#dec5a5')
            d.rounded_rectangle((225,69,421,339),radius=57,fill='#e5a25f')
            phone(d,243,86,1.52,'#f18430','#f7d4a6')
            for x,y in [(115,130),(435,210),(151,272)]:d.ellipse((x,y,x+62,y+62),fill='#de9658');d.arc((x+7,y+8,x+55,y+52),190,275,fill='#f5c18d',width=4)
        elif key=='flat':
            d.ellipse((100,40,515,415),fill='#f7cf98');d.rectangle((32,280,196,369),fill=INK);phone(d,249,79,1.65)
            d.polygon([(433,90),(544,165),(430,205)],fill=INK)
        elif key=='macro':
            phone(d,40,-82,4.0,ORANGE,INK)
            for i in range(18):d.line((550+i*5,0,500+i*8,440),fill='#eabb79',width=2)
        elif key=='collage':
            d.polygon([(65,60),(417,83),(377,399),(25,364)],fill='#dfd0b9')
            d.rectangle((167,123,590,263),fill=ORANGE)
            phone(d,249,95,1.65,INK)
            d.polygon([(458,45),(518,55),(490,340),(430,330)],fill='#fbe4c5')
            for y in range(285,340,12):d.line((61,y,196,y),fill=INK,width=3)
        elif key=='comic':
            d.rectangle((18,18,622,422),outline=INK,width=9)
            for x in range(35,630,19):
                for y in range(35,430,19):d.ellipse((x,y,x+3,y+3),fill='#e6b576')
            for i in range(20):
                a=i*math.pi/10;d.line((320+120*math.cos(a),215+120*math.sin(a),320+600*math.cos(a),215+600*math.sin(a)),fill=INK,width=3)
            phone(d,254,88,1.6,INK,'#ffab35')
        elif key=='glass':
            for i in range(8):d.ellipse((190+i*7,306+i*2,470-i*7,368-i*2),outline='#e9cbb0',width=2)
            d.rounded_rectangle((235,65,417,340),radius=30,fill='#f7e5d1',outline='#d2b79d',width=3)
            d.rounded_rectangle((248,75,401,324),radius=22,outline='white',width=4)
            d.ellipse((280,137,372,232),fill='#ffad52',outline='#ff7900',width=3)
            d.line((250,89,250,295),fill='white',width=7)
        elif key=='editorial':
            d.rectangle((60,0,212,440),fill='#ead9bf');d.line((125,0,125,440),fill=CREAM,width=10)
            person(d,320,110,True,INK);phone(d,357,179,.9)
            d.ellipse((259,235,383,271),fill=INK)
        elif key=='film':
            im=Image.new('RGB',(W,H),'#4a342a');d=ImageDraw.Draw(im)
            d.ellipse((72,-60,400,280),fill='#7c5434');person(d,304,104,False,'#242b2b');phone(d,358,180,.9)
            rng=random.Random(91)
            for _ in range(12000):
                x,y=rng.randrange(W),rng.randrange(H);p=im.getpixel((x,y));v=rng.randint(-10,10);im.putpixel((x,y),tuple(max(0,min(255,n+v)) for n in p))
        else:
            shadow=Image.new('RGBA',(W,H));sd=ImageDraw.Draw(shadow);sd.ellipse((170,315,500,386),fill=(80,60,40,70));shadow=shadow.filter(ImageFilter.GaussianBlur(15));im=Image.alpha_composite(im.convert('RGBA'),shadow).convert('RGB');d=ImageDraw.Draw(im)
            phone(d,241,53,1.75)
            d.line((256,81,256,288),fill='#ffb363',width=5)
    im.save(OUT/(s['id']+'.png'), optimize=True)
print('Built 26 original visual guides and storyboards')
