from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from app import prompt_package as pp, pipeline
from app.llm import LLMError
from app.config import settings


def brand():
    return SimpleNamespace(name='راه بوم', industry='AI', description='فروش اشتراک', products=[], audience='برنامه‌نویسان', tone='صمیمی', cta='@rahboom1', forbidden_topics=[], hashtags=['راه_بوم'], language='fa')


def response(video=False):
    frame={'prompt':'Detailed camera composition and light. '*8, 'on_screen_text':'راه بوم', 'dialogue':'پسر: چی می‌خوای؟ دختر: ابزار مناسب کارم.' if video else ''}
    return {'title':'راهنمای خريد', 'visual_style':'Natural restrained lighting and continuity. '*6, 'caption':'مي خواهيد؟ @rahboom1 https://rahboom.com', 'hashtags':['#راه_بوم'], 'frames':[frame, {**frame, 'dialogue':''}] if video else [frame]}


def test_video_timing_and_reference_requirement(monkeypatch):
    call=Mock(return_value=response(True));monkeypatch.setattr(pp,'chat_json',call)
    p=SimpleNamespace(post_type='video_prompt',mode='video',topic_hint='کلاد',content={'target_seconds':40})
    d=pp.generate_package(brand(),p)
    assert d['target_seconds']==10 and d['requires_character_references']
    assert 'می‌خواهید' in d['caption'] and '@rahboom1' in d['caption']
    assert d['hashtags']==['راه_بوم']
    assert any('8–10' in b['label'] for b in d['blocks'])
    assert 'do NOT invent' in call.call_args.args[1]


def test_no_media_calls_or_offline_success(monkeypatch):
    monkeypatch.setattr(settings,'prompt_only',True)
    monkeypatch.setattr(pp,'chat_json',Mock(return_value=response()))
    render=Mock(side_effect=AssertionError('Must not render'));image=Mock(side_effect=AssertionError('Must not generate'))
    monkeypatch.setattr(pipeline,'_render',render);monkeypatch.setattr(pipeline,'_image',image)
    p=SimpleNamespace(brand_id='b',post_type='sales',mode='single',topic_hint='',content={},slides=['old'])
    pipeline.run_post(SimpleNamespace(get=lambda *a: brand()),p)
    assert p.slides==[] and p.content['output_kind']=='prompt_package'
    monkeypatch.setattr(pp,'chat_json',Mock(side_effect=LLMError('unavailable')))
    with pytest.raises(LLMError):pipeline.run_post(SimpleNamespace(get=lambda *a: brand()),p)
    render.assert_not_called();image.assert_not_called()


def test_reject_incomplete_package(monkeypatch):
    monkeypatch.setattr(pp,'chat_json',lambda *a,**k: response())
    with pytest.raises(LLMError):pp.generate_package(brand(),SimpleNamespace(post_type='video_prompt',mode='video',topic_hint='',content={}))
