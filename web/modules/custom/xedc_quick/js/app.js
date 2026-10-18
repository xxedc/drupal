(function (Drupal, drupalSettings, once) {
  Drupal.behaviors.xq = {
    attach(ctx) {
      const root = once('xq', '#xq-app', ctx)[0];
      if (!root) return;
      const esc = s => String(s).replace(/</g, '&lt;');
      const opts = a => (a || []).map(n => `<option value="${esc(n).replace(/"/g, '&quot;')}">`).join('');
      const X = drupalSettings.xq || {};
      root.innerHTML = `
<input id="xq-title" placeholder="标题">
<input id="xq-model" list="dl-m" placeholder="人物名字（选已有或直接输入新的）"><datalist id="dl-m">${opts(X.models)}</datalist>
<div id="xq-tagschips" class="xq-chips"></div><input id="xq-tags" list="dl-t" placeholder="标签：选已有或输入新的，回车添加"><datalist id="dl-t">${opts(X.tags)}</datalist>
<div id="xq-catschips" class="xq-chips"></div><input id="xq-cats" list="dl-c" placeholder="分类栏目：选已有或输入新的，回车添加"><datalist id="dl-c">${opts(X.cats)}</datalist>
<label class="xq-btn">选择照片<input id="xq-files" type="file" accept="image/*" multiple hidden></label>
<div id="xq-bar">已传 0 / 0</div>
<div id="xq-grid"></div>
<label><input id="xq-pub" type="checkbox"> 直接发布（不勾选则存草稿）</label>
<button id="xq-go" class="xq-btn xq-primary">上传并创建草稿</button>
<div id="xq-msg"></div>`;
      const $ = s => root.querySelector(s);
      const msg = t => { $('#xq-msg').textContent = t; };
      let items = [], cover = null, token;
      const sets = { tags: [], cats: [] };
      function chips(k) {
        const box = $('#xq-' + k + 'chips');
        box.innerHTML = '';
        sets[k].forEach((n, i) => {
          const sp = document.createElement('span');
          sp.textContent = n + ' ×';
          sp.onclick = () => { sets[k].splice(i, 1); chips(k); };
          box.appendChild(sp);
        });
      }
      function addChip(k) {
        const inp = $('#xq-' + k);
        inp.value.split(/[,，]/).map(x => x.trim()).filter(Boolean).forEach(n => { if (!sets[k].includes(n)) sets[k].push(n); });
        inp.value = '';
        chips(k);
      }
      ['tags', 'cats'].forEach(k => {
        const inp = $('#xq-' + k);
        inp.oninput = e => { if (!e.inputType || e.inputType === 'insertReplacementText') addChip(k); };
        inp.onchange = () => addChip(k);
        inp.onkeydown = e => { if (e.key === 'Enter') { e.preventDefault(); addChip(k); } };
      });

      function draw() {
        const g = $('#xq-grid');
        g.innerHTML = '';
        items.forEach((it, i) => {
          const d = document.createElement('div');
          d.className = 'xq-it ' + it.st + (it.dup ? ' dup' : '');
          d.innerHTML = `<img src="${it.thumb}"><b>${i + 1}</b>${it === cover ? '<u>封面</u>' : ''}`;
          d.onclick = () => menu(it);
          g.appendChild(d);
        });
        $('#xq-bar').textContent = `已传 ${items.filter(x => x.st === 'ok').length} / ${items.length}`;
      }

      function menu(it) {
        const a = prompt('1 设为封面\n2 删除\n3 前移一位\n4 移到最前');
        const i = items.indexOf(it);
        if (a === '1') cover = it;
        else if (a === '2') { items.splice(i, 1); if (cover === it) cover = items[0] || null; }
        else if (a === '3' && i > 0) [items[i - 1], items[i]] = [items[i], items[i - 1]];
        else if (a === '4') { items.splice(i, 1); items.unshift(it); }
        draw();
      }

      async function scaled(file, max, type, q) {
        const bm = await createImageBitmap(file);
        const r = Math.min(1, max / Math.max(bm.width, bm.height));
        const c = document.createElement('canvas');
        c.width = Math.round(bm.width * r);
        c.height = Math.round(bm.height * r);
        c.getContext('2d').drawImage(bm, 0, 0, c.width, c.height);
        bm.close();
        let b = await new Promise(ok => c.toBlob(ok, type, q));
        if (type === 'image/webp' && b.type !== 'image/webp') {
          b = await new Promise(ok => c.toBlob(ok, 'image/jpeg', 0.85));
        }
        return b;
      }

      $('#xq-files').onchange = async e => {
        const fs = [...e.target.files];
        e.target.value = '';
        for (const f of fs) {
          try {
            const t = await scaled(f, 240, 'image/jpeg', 0.6);
            items.push({ file: f, thumb: URL.createObjectURL(t), st: 'wait' });
          } catch (err) {}
          if (items.length % 10 === 0) draw();
        }
        if (!cover) cover = items[0] || null;
        draw();
      };

      async function up(it, n, title) {
        token = token || await (await fetch('/session/token')).text();
        for (let k = 0; k < 3; k++) {
          try {
            const b = await Promise.race([scaled(it.file, 2000, 'image/webp', 0.82), new Promise((_, no) => setTimeout(() => no('压缩超时'), 30000))]);
            const fd = new FormData();
            fd.append('file', b, 'x.' + (b.type === 'image/webp' ? 'webp' : 'jpg'));
            fd.append('title', title);
            fd.append('n', n);
            fd.append('orig', it.file.size);
            const r = await fetch('/admin/quick-gallery/upload', { method: 'POST', body: fd, headers: { 'X-CSRF-Token': token }, signal: AbortSignal.timeout(60000) });
            if (!r.ok) throw 'HTTP ' + r.status;
            const j = await r.json();
            it.mid = j.mid;
            it.dup = !!j.dup;
            it.st = 'ok';
            return;
          } catch (e) { it.err = String(e); }
        }
        it.st = 'bad';
      }

      async function run(title) {
        const q = items.filter(x => x.st !== 'ok');
        let p = 0;
        const w = async () => {
          while (p < q.length) {
            const it = q[p++];
            it.st = 'up';
            draw();
            await up(it, items.indexOf(it) + 1, title);
            draw();
          }
        };
        await Promise.all([w(), w()]);
      }

      $('#xq-pub').onchange = () => { $('#xq-go').textContent = $('#xq-pub').checked ? '上传并发布' : '上传并创建草稿'; };
      $('#xq-go').onclick = async () => {
        const btn = $('#xq-go');
        addChip('tags'); addChip('cats');
        const title = $('#xq-title').value.trim();
        if (!title || !items.length) return msg('请填标题并选择照片');
        btn.disabled = true;
        msg('上传中…');
        await run(title);
        const dn = items.filter(x => x.dup).length;
        if (dn) msg(dn + ' 张已存在，已复用');
        if (items.some(x => x.st !== 'ok')) { btn.disabled = false; return msg('有失败的图：' + items.filter(x => x.st !== 'ok').map(x => x.err).join(' ') + ' 再点一次重试'); }
        const r = await fetch('/admin/quick-gallery/create', {
          method: 'POST',
          headers: { 'X-CSRF-Token': token, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            title,
            model: $('#xq-model').value,
            tags: sets.tags,
            cats: sets.cats,
            mids: items.map(x => x.mid),
            cover: (cover || items[0]).mid,
            publish: $('#xq-pub').checked,
          }),
        });
        const j = await r.json();
        if (r.ok) location.href = j.edit;
        else { msg(j.error || '创建失败'); btn.disabled = false; }
      };
    },
  };
})(Drupal, drupalSettings, once);
