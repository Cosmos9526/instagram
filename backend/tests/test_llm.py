from unittest.mock import Mock
import pytest
from app import llm


def test_reject_truncated_output(monkeypatch):
    response=Mock(status_code=200)
    response.json.return_value={'choices':[{'finish_reason':'length','message':{'content':'{"ok": true}'}}]}
    monkeypatch.setattr(llm.httpx,'post',lambda *a,**k:response)
    with pytest.raises(llm.LLMError,match='truncated'):llm._post('https://example.test',{}, {})


def test_fallback_requests_complete_json(monkeypatch):
    monkeypatch.setattr(llm.settings,'llm_provider','openai_compat')
    monkeypatch.setattr(llm.settings,'llm_api_key','')
    monkeypatch.setattr(llm.settings,'llm_fallback_url','https://example.test')
    call=Mock(return_value={'ok':True});monkeypatch.setattr(llm,'_post',call)
    assert llm.chat_json('system','user')=={'ok':True}
    assert call.call_args.args[2]['max_tokens']==6000
    assert call.call_args.args[2]['response_format']=={'type':'json_object'}
