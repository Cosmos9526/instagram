from datetime import date
from fastapi.testclient import TestClient
from app.main import app
from app.weekly_prompts import package

def test_seven_complete_distinct_prompts():
    content=[package(i,date(2026,9,26)) for i in range(7)]
    assert len({p['title'] for p in content})==7
    assert len({p['blocks'][1]['text'] for p in content})==7
    for p in content:
        assert p['source']=='editorial'
        assert len(p['full_prompt'].split())>500
        assert p['blocks'][1]['text'] in p['full_prompt']
        assert len(p['blocks'][1]['text'].split())<=26
        assert '8.00–10.00' in p['full_prompt'] and '@rahboom1' in p['full_prompt']

def test_week_api_is_private_idempotent_and_ready():
    with TestClient(app) as c:
        token=c.post('/auth/register',json={'email':'week@example.com','password':'test-pass-123','name':'Owner'}).json()['token']
        h={'Authorization':'Bearer '+token}
        b=c.post('/brands',headers=h,json={'name':'Rahboom','industry':'AI','website':'https://rahboom.com'}).json()['id']
        url=f'/brands/{b}/weekly-prompts'
        assert c.post(url).status_code==401
        r=c.post(url,headers=h)
        assert r.status_code==200,r.text
        posts=r.json()
        assert len(posts)==7 and len({p['for_date'] for p in posts})==7
        assert all(p['status']=='ready' and p['post_type']=='video_prompt' for p in posts)
        assert [p['id'] for p in posts]==[p['id'] for p in c.post(url,headers=h).json()]
