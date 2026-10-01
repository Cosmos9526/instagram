from fastapi.testclient import TestClient
from app.main import app


def test_catalog_offers_distinct_complete_original_styles():
    with TestClient(app) as client:
        response = client.get('/catalog')
    assert response.status_code == 200
    styles = response.json()['prompt_styles']
    assert len(styles) == 26
    assert len({s['id'] for s in styles}) == len(styles)
    assert len({s['prompt'] for s in styles}) == len(styles)
    assert sum(s['kind'] == 'video' for s in styles) == 14
    for style in styles:
        assert style['preview_label']
        with TestClient(app) as client:
            preview = client.get(style['preview'])
        assert preview.status_code == 200
        assert preview.headers['content-type'] == 'image/png'
        assert '{{brief}}' in style['prompt'] and '{{brand}}' in style['prompt']
        assert '{{brief}}' in style['cover_prompt']
        assert style['name_fa'] and style['provenance'] == 'Original Rahboom template'
        if style['kind'] == 'video':
            assert '8.0–10.0s END CARD' in style['prompt']
            assert 'Persian dialogue' in style['prompt']
            assert style['video_style']
        else:
            assert '1080x1350' in style['prompt']
