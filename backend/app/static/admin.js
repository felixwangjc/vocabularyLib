'use strict';
const $ = id => document.getElementById(id);
let csrf = '', items = [], editing = null, dirty = false, busy = false, view = 'contents';
const uid = () => crypto.randomUUID().replaceAll('-', '');
const blankLine = (speaker = 'A') => ({id: uid(), speaker, en: '', zh: '', isTarget: false});
const blankScene = () => ({id: uid(), titleZh: '', lines: [blankLine('A'), blankLine('B')], assetId: null, altZh: ''});
function toast(message) { $('toast').textContent = message; $('toast').hidden = false; clearTimeout(toast.timer); toast.timer = setTimeout(() => $('toast').hidden = true, 4500); }
async function api(path, options = {}) {
  const headers = {...options.headers};
  if (options.body && !(options.body instanceof Blob)) headers['Content-Type'] = 'application/json';
  if (options.method && options.method !== 'GET') headers['X-CSRF-Token'] = csrf;
  const response = await fetch('/api' + path, {...options, headers, credentials: 'same-origin'});
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401 && path !== '/login') showLogin();
    const detail = Array.isArray(data.detail) ? data.detail.map(x => x.msg).join('；') : data.detail;
    throw new Error(detail || '网络请求失败，请稍后重试');
  }
  return data;
}
function element(tag, className, text) { const node = document.createElement(tag); if (className) node.className = className; if (text !== undefined) node.textContent = text; return node; }
function button(text, className, action) { const node = element('button', className, text); node.type = 'button'; node.addEventListener('click', action); return node; }
function field(label, value, change, {textarea = false, placeholder = '', required = true} = {}) {
  const wrapper = element('label', '', label), input = element(textarea ? 'textarea' : 'input');
  input.value = value || ''; input.required = required; input.maxLength = 2000; input.placeholder = placeholder;
  if (textarea) input.rows = 2;
  input.addEventListener('input', () => { change(input.value); markDirty(); }); wrapper.append(input); return wrapper;
}
function markDirty() { dirty = true; $('save-note').textContent = '有未保存的修改'; }
function setBusy(state) { busy = state; document.querySelectorAll('#editor-form input, #editor-form textarea, #editor-form select, #editor-form button').forEach(node => node.disabled = state); $('save').textContent = state ? '正在保存…' : '保存内容'; }
function confirmAction(title, message, images = false, okText = '确认删除') {
  $('confirm-title').textContent = title; $('confirm-message').textContent = message;
  $('delete-images-label').hidden = !images; $('delete-images').checked = true; $('confirm-ok').textContent = okText;
  $('confirm-dialog').showModal();
  return new Promise(resolve => {
    const finish = accepted => { $('confirm-dialog').close(); $('confirm-ok').onclick = null; $('confirm-cancel').onclick = null; $('confirm-dialog').oncancel = null; resolve({accepted, images: images && $('delete-images').checked}); };
    $('confirm-ok').onclick = () => finish(true); $('confirm-cancel').onclick = () => finish(false);
    $('confirm-dialog').oncancel = event => { event.preventDefault(); finish(false); };
  });
}
async function canLeave() { if (busy) return false; if (!dirty) return true; return (await confirmAction('放弃未保存的修改？', '已保存的内容不会受到影响，新上传但未使用的图片可在图片素材中删除。', false, '放弃修改')).accepted; }
function showLogin() { $('login-view').hidden = false; $('app-view').hidden = true; csrf = ''; }
async function showApp() { $('login-view').hidden = true; $('app-view').hidden = false; await loadContents(); }
async function loadContents() {
  try { items = (await api('/contents')).items; renderContents(); } catch (e) { toast(e.message); }
}
function renderContents() {
  $('count-all').textContent = items.length; $('count-published').textContent = items.filter(x => x.status === 'published').length; $('count-draft').textContent = items.filter(x => x.status === 'draft').length;
  const query = $('search').value.toLowerCase(), status = $('filter-status').value;
  const filtered = items.filter(x => (status === 'all' || x.status === status) && [x.phrase, x.meaningZh, x.category].join(' ').toLowerCase().includes(query));
  $('content-list').replaceChildren();
  if (!filtered.length) { $('content-list').append(element('div', 'empty', items.length ? '没有匹配的内容，试试其他关键词。' : '还没有内容，点击「添加内容」开始你的第一个故事。')); return; }
  for (const item of filtered) {
    const card = element('article', 'content-card'), copy = element('div'), top = element('div', 'card-top');
    top.append(element('span', 'badge ' + (item.status === 'published' ? 'published' : ''), item.status === 'published' ? '已发布' : '草稿'), element('span', 'category', item.category));
    copy.append(top, element('h3', '', item.phrase), element('p', '', item.meaningZh));
    card.append(copy, button('编辑 →', 'secondary', () => openContent(item.id))); $('content-list').append(card);
  }
}
function setView(next) {
  view = next;
  $('contents-view').hidden = next !== 'contents'; $('assets-view').hidden = next !== 'assets'; $('editor-view').hidden = next !== 'editor';
  $('nav-contents').classList.toggle('active', next !== 'assets'); $('nav-assets').classList.toggle('active', next === 'assets');
  $('page-title').textContent = next === 'assets' ? '图片素材' : '内容管理';
  $('page-subtitle').textContent = next === 'assets' ? '每个情景，一张记忆的线索。' : '把日常表达，变成容易记住的小故事。';
  $('new-content').hidden = next === 'editor';
}
async function openContent(id) {
  if (!(await canLeave())) return;
  try { editing = await api('/contents/' + id); dirty = false; renderEditor(); } catch (e) { toast(e.message); }
}
function renderEditor() {
  setView('editor'); $('editor-title').textContent = editing.id ? '编辑内容' : '添加内容'; $('editor-state').textContent = editing.status === 'published' ? '已发布' : '草稿';
  $('phrase').value = editing.phrase; $('meaning').value = editing.meaningZh; $('category').value = editing.category; $('usage').value = editing.usageNoteZh; $('publish-status').value = editing.status;
  $('delete-content').hidden = !editing.id; $('save-note').textContent = dirty ? '有未保存的修改' : '修改后记得保存'; renderScenes(); window.scrollTo({top: 0});
}
function renderScenes() {
  $('scenarios').replaceChildren();
  editing.scenarios.forEach((scene, sceneIndex) => {
    const panel = element('section', 'panel'), heading = element('div', 'scene-heading');
    heading.append(element('h3', '', '情景 ' + (sceneIndex + 1)));
    if (editing.scenarios.length > 1) heading.append(button('移除情景', 'text-button', async () => {
      if ((await confirmAction('移除这个情景？', '保存内容后生效，配图文件仍可在图片素材中管理。', false, '移除情景')).accepted) { editing.scenarios.splice(sceneIndex, 1); markDirty(); renderScenes(); }
    }));
    panel.append(heading, field('情景标题', scene.titleZh, value => scene.titleZh = value, {placeholder: '例如：累了一天，只想在家休息'}));
    const lines = element('div');
    scene.lines.forEach((line, lineIndex) => {
      const row = element('div', 'line-card'), bar = element('div', 'line-toolbar'), speaker = element('input', 'speaker-input');
      speaker.value = line.speaker; speaker.required = true; speaker.maxLength = 30; speaker.setAttribute('aria-label', '说话人'); speaker.addEventListener('input', () => {line.speaker = speaker.value; markDirty();});
      const target = element('label', 'checkbox-row'), checkbox = element('input'); checkbox.type = 'checkbox'; checkbox.checked = line.isTarget; checkbox.addEventListener('change', () => { line.isTarget = checkbox.checked; markDirty(); }); target.append(checkbox, document.createTextNode('重点表达'));
      bar.append(speaker, target);
      if (scene.lines.length > 1) bar.append(button('删除这句', 'text-button', () => { scene.lines.splice(lineIndex, 1); markDirty(); renderScenes(); }));
      row.append(bar, field('英文对话', line.en, value => line.en = value, {textarea: true, placeholder: '输入英文台词'}), field('中文翻译', line.zh, value => line.zh = value, {textarea: true, placeholder: '输入中文翻译'})); lines.append(row);
    });
    panel.append(lines);
    if (scene.lines.length < 12) panel.append(button('＋ 添加一句对话', 'secondary full', () => { scene.lines.push(blankLine(scene.lines.length % 2 ? 'B' : 'A')); markDirty(); renderScenes(); }));
    const imageEditor = element('div', 'image-editor');
    if (scene.assetId) { const img = element('img'); img.src = '/api/assets/' + scene.assetId + '/image'; img.alt = scene.altZh || '情景配图'; imageEditor.append(img); }
    else imageEditor.append(element('div', 'image-placeholder', '还没有情景配图'));
    const controls = element('div', 'image-controls'), uploadLabel = element('label', '', scene.assetId ? '替换配图' : '上传配图'), upload = element('input');
    upload.type = 'file'; upload.accept = 'image/jpeg,image/png,image/webp';
    upload.addEventListener('change', async () => {
      const file = upload.files[0]; if (!file) return;
      if (file.size > 5 * 1024 * 1024) { toast('图片不能超过 5 MB'); upload.value = ''; return; }
      setBusy(true); upload.disabled = true;
      try { const result = await api('/assets', {method: 'POST', body: file, headers: {'Content-Type': file.type}}); scene.assetId = result.id; markDirty(); renderScenes(); toast('配图已上传，保存内容后生效'); }
      catch (e) { toast(e.message); } finally { setBusy(false); upload.disabled = false; }
    });
    uploadLabel.append(upload); controls.append(uploadLabel, element('p', '', 'JPEG / PNG / WebP · 最大 5 MB · 最长边 4096px'), field('图片说明', scene.altZh, value => scene.altZh = value, {placeholder: '描述画面，便于理解和无障碍阅读', required: false}));
    if (scene.assetId) controls.append(button('移除配图', 'text-button', () => { scene.assetId = null; editing.status = 'draft'; $('publish-status').value = 'draft'; markDirty(); renderScenes(); toast('已移除配图，将保存为草稿'); }));
    imageEditor.append(controls); panel.append(imageEditor); $('scenarios').append(panel);
  });
  $('add-scenario').hidden = editing.scenarios.length >= 10;
}
async function loadAssets() {
  $('asset-grid').replaceChildren(element('p', 'muted', '正在加载素材…'));
  try {
    const assets = (await api('/assets')).items; $('asset-grid').replaceChildren();
    if (!assets.length) $('asset-grid').append(element('div', 'empty', '在内容编辑器中上传配图，它们会显示在这里。'));
    for (const asset of assets) {
      const card = element('article', 'asset-card'), img = element('img'); img.src = '/api/assets/' + asset.id + '/image'; img.alt = asset.altZh || '情景插图'; img.loading = 'lazy';
      const info = element('div', 'asset-info'), count = (asset.references || []).length;
      info.append(element('span', 'badge ' + (count ? 'published' : ''), count ? '已被 ' + count + ' 条内容使用' : '未使用'), element('p', '', `${asset.width} × ${asset.height} · ${asset.contentType}`));
      const remove = button(asset.state === 'deleting' ? '重试删除图片' : '删除图片', 'danger', async () => {
        if (!(await confirmAction('删除图片文件？', '将删除云端图片文件。已下载到 App 的图片缓存不会立即消失。')).accepted) return;
        remove.disabled = true;
        try { await api('/assets/' + asset.id, {method: 'DELETE'}); toast('图片已删除'); await loadAssets(); } catch (e) { toast(e.message); remove.disabled = false; }
      });
      remove.disabled = count > 0; remove.title = count ? '请先从引用的内容中移除并保存' : ''; info.append(remove); card.append(img, info); $('asset-grid').append(card);
    }
  } catch (e) { toast(e.message); }
}
$('login-form').addEventListener('submit', async event => {
  event.preventDefault(); const submit = event.submitter; submit.disabled = true; $('login-error').textContent = '';
  try { const result = await api('/login', {method: 'POST', body: JSON.stringify({password: $('password').value})}); csrf = result.csrfToken; $('password').value = ''; await showApp(); }
  catch (e) { $('login-error').textContent = e.message; } finally { submit.disabled = false; }
});
$('logout').addEventListener('click', async () => { if (!(await canLeave())) return; try {await api('/logout', {method:'POST'}); dirty = false; showLogin();} catch(e) {toast(e.message);} });
$('new-content').addEventListener('click', async () => {if (!(await canLeave())) return; editing = {baseRevision: null, phrase:'', meaningZh:'', category:'affirmation', usageNoteZh:'', status:'draft', scenarios:[blankScene()]}; dirty = false; renderEditor();});
$('nav-contents').addEventListener('click', async () => { if (!(await canLeave())) return; dirty = false; setView('contents'); await loadContents(); });
$('back').addEventListener('click', () => $('nav-contents').click());
$('nav-assets').addEventListener('click', async () => { if (!(await canLeave())) return; dirty = false; setView('assets'); await loadAssets(); });
$('search').addEventListener('input', renderContents); $('filter-status').addEventListener('change', renderContents); $('refresh').addEventListener('click', loadContents);
for (const [id, key] of [['phrase','phrase'],['meaning','meaningZh'],['category','category'],['usage','usageNoteZh'],['publish-status','status']]) $(id).addEventListener('input', () => {editing[key] = $(id).value; markDirty();});
$('add-scenario').addEventListener('click', () => {if(editing.scenarios.length < 10) {editing.scenarios.push(blankScene()); markDirty(); renderScenes();}});
$('editor-form').addEventListener('submit', async event => {
  event.preventDefault(); if (busy) return; setBusy(true);
  try {
    const {id, ...payload} = editing;
    const result = await api(id ? '/contents/' + id : '/contents', {method: id ? 'PUT' : 'POST', body: JSON.stringify(payload)});
    dirty = false; editing = await api('/contents/' + result.id); renderEditor(); await loadContents(); toast('内容已保存' + (editing.status === 'published' ? '并加入每日推荐' : '为草稿'));
  } catch(e) {toast(e.message);} finally {setBusy(false);}
});
$('delete-content').addEventListener('click', async () => {
  if (busy) return;
  const confirmation = await confirmAction('删除这条内容？', '标题和全部情景对话将从后台列表和每日推荐中移除。历史版本会保留以便管理员恢复。', true);
  if (!confirmation.accepted) return; setBusy(true);
  try {
    const result = await api('/contents/' + editing.id, {method:'DELETE', body:JSON.stringify({baseRevision:editing.baseRevision})});
    let failures = 0;
    if (confirmation.images) for (const id of result.unlinkedAssets) {try {await api('/assets/'+id,{method:'DELETE'});} catch {failures++;}}
    dirty = false; editing = null; setView('contents'); await loadContents(); toast(failures ? '内容已删除；部分图片仍被引用或删除失败，可在图片素材中检查' : '内容已删除');
  } catch(e) {toast(e.message);} finally {setBusy(false);}
});
window.addEventListener('beforeunload', event => {if(dirty){event.preventDefault();event.returnValue='';}});
(async () => {try {csrf = (await api('/session')).csrfToken; await showApp();} catch {showLogin();}})();
