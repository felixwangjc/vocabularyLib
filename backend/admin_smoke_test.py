"""Exercise only a newly created disposable item; existing content is never edited."""
from copy import deepcopy
from pathlib import Path
import argparse
import json
import requests

ROOT = Path(__file__).resolve().parent

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('origin')
    parser.add_argument('--public-api', required=True)
    args = parser.parse_args()
    password = next(line.split('：',1)[1] for line in (ROOT / '.admin-access.txt').read_text().splitlines() if line.startswith('管理密码：'))
    base = args.origin.rstrip('/')
    # Pin today's real recommendation before briefly publishing a test fixture.
    original = requests.get(args.public_api, timeout=60)
    original.raise_for_status()
    assert requests.get(base + '/api/contents', timeout=60).status_code == 401
    session = requests.Session()
    session.headers['Origin'] = base
    result = session.post(base + '/api/login', json={'password': password}, timeout=60)
    result.raise_for_status()
    session.headers['X-CSRF-Token'] = result.json()['csrfToken']
    def call(method, path, **kwargs):
        result = session.request(method, base + '/api' + path, timeout=60, **kwargs)
        result.raise_for_status()
        return result.json()
    before = call('GET','/contents')['items']
    asset = call('POST','/assets', data=(ROOT / 'content/assets/after-work-ramen.jpg').read_bytes(), headers={'Content-Type':'image/jpeg'})
    item = {'phrase':'Admin verification fixture', 'meaningZh':'后台临时验证内容', 'category':'verification',
            'usageNoteZh':'测试完成后删除', 'status':'draft', 'baseRevision':None,
            'scenarios':[{'id':'scene', 'titleZh':'新增情景验证', 'assetId':asset['id'], 'altZh':'测试卡通配图',
                          'lines':[{'id':'line','speaker':'A','en':'Honestly, valid.','zh':'完全可以理解。','isTarget':True}]}]}
    created = call('POST','/contents',json=item)
    content_id = created['id']
    try:
        read = call('GET','/contents/'+content_id)
        assert read['status']=='draft' and read['scenarios'][0]['assetId']==asset['id']
        assert session.get(base+'/api/assets/'+asset['id']+'/image',timeout=60).status_code==200
        item.update(baseRevision=created['revision'],status='published',phrase='Edited verification title')
        item['scenarios'][0]['titleZh']='修改后的情景标题'
        item['scenarios'][0]['lines'][0]['zh']='修改后的对话内容'
        updated = call('PUT','/contents/'+content_id,json=item)
        saved = call('GET','/contents/'+content_id)
        assert saved['phrase']=='Edited verification title' and saved['scenarios'][0]['lines'][0]['zh']=='修改后的对话内容'
        conflict=session.put(base+'/api/contents/'+content_id,json=item,timeout=60)
        assert conflict.status_code==409
        assert session.delete(base+'/api/assets/'+asset['id'],timeout=60).status_code==409
        saved.pop('id'); saved['status']='draft'; saved['scenarios'][0]['assetId']=None
        removed = call('PUT','/contents/'+content_id,json=saved)
        call('DELETE','/assets/'+asset['id'])
        assert session.get(base+'/api/assets/'+asset['id']+'/image',timeout=60).status_code==404
        call('DELETE','/contents/'+content_id,json={'baseRevision':removed['revision']})
        assert session.get(base+'/api/contents/'+content_id,timeout=60).status_code==404
        after=call('GET','/contents')['items']
        assert {x['id'] for x in before}=={x['id'] for x in after}
        current=requests.get(args.public_api,timeout=60);current.raise_for_status()
        assert original.json()['slang']==current.json()['slang']
        print(json.dumps({'result':'passed','checks':['anonymous denied','login','private upload and preview','draft create','title and dialogue edit','publish','stale edit 409','referenced image deletion 409','remove image','delete image','delete content','existing daily content unchanged'],'testContentId':content_id},ensure_ascii=False,indent=2))
    except Exception:
        print('Verification failed; disposable content ID:',content_id,'asset ID:',asset['id'])
        raise
