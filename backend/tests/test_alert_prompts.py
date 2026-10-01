from fastapi.testclient import TestClient
from sqlalchemy import select, delete
import pytest
from app.main import app
from app.db import SessionLocal
from app.models import MarketAlert, Job, Post
from app.alert_prompts import prepare_top_alerts


@pytest.fixture(autouse=True)
def clean_test_alert():
    yield
    with SessionLocal() as db:
        alert = db.scalar(select(MarketAlert).where(MarketAlert.fingerprint == 'test-prompt-news'))
        if alert:
            for post in db.scalars(select(Post).where(Post.content['alert_id'].as_string() == alert.id)):
                db.execute(delete(Job).where(Job.post_id == post.id))
                db.delete(post)
            db.delete(alert)
            db.commit()


def test_news_prompt_is_private_source_bound_and_reused():
    with TestClient(app) as client:
        token = client.post('/auth/register', json={'email':'news-prompts@example.com','password':'test-pass-123','name':'Owner'}).json()['token']
        headers = {'Authorization':'Bearer '+token}
        brand = client.post('/brands',headers=headers,json={'name':'Rahboom','industry':'AI','website':'https://rahboom.com'}).json()['id']
        with SessionLocal() as db:
            alert = MarketAlert(fingerprint='test-prompt-news',title='A specific new feature',summary='A source-grounded summary',url='https://source.test/story',source='Official example',category='news',importance=5)
            db.add(alert);db.commit();alert_id=alert.id
        path = f'/brands/{brand}/alerts/{alert_id}/prompt'
        assert client.post(path).status_code == 401
        first = client.post(path,headers=headers).json()
        second = client.post(path,headers=headers).json()
        assert first['id']==second['id']
        assert first['content']['source_url']=='https://source.test/story'
        with SessionLocal() as db:
            assert 'A source-grounded summary' in db.get(Post,first['id']).topic_hint
            assert len(list(db.scalars(select(Job).where(Job.post_id==first['id']))))==1
            prepare_top_alerts(db)
            assert len(list(db.scalars(select(Job).where(Job.post_id==first['id']))))==1
            post=db.get(Post,first['id']);post.status='ready';post.content={**post.content,'full_prompt':'Prepared news prompt','output_kind':'prompt_package'};db.commit()
        cached=client.post(path,headers=headers).json()
        assert cached['status']=='ready' and cached['content']['full_prompt']=='Prepared news prompt'
