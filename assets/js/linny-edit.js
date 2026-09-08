/* Linny in-page note editor.
 *
 * Loaded by layouts/partials/linny-edit.html on single pages, only when
 * `params.linnyEdit` is on AND the build environment is "development" -- so it
 * can never reach a published site.
 *
 * It swaps the rendered article for a textarea holding the note's RAW Markdown
 * source, front matter included, and PUTs it back to a save endpoint the
 * NOTEBOOK provides (a theme cannot write files). Hugo re-renders from the
 * saved source, so what you see afterwards is the real build -- never an
 * HTML-to-Markdown guess, which would mangle code fences, shortcodes and
 * front matter.
 *
 * The endpoint contract, both relative to the site's contentDir:
 *
 *   GET  <linny-edit-api>/api/note?path=<note>.md  -> 200, raw markdown body
 *   PUT  <linny-edit-api>/api/note?path=<note>.md  -> 200 once written
 *
 * linny-notebook-template ships a conforming one (edit-server.py, started by
 * start-web.sh). Any notebook can substitute its own.
 */
(function () {
  var meta = document.querySelector('meta[name="linny-source"]');
  if (!meta) return; // not a note (taxonomy / list page)

  var source = meta.content;
  var apiMeta = document.querySelector('meta[name="linny-edit-api"]');
  var api = (apiMeta && apiMeta.content) || 'http://localhost:9998';
  var url = api + '/api/note?path=' + encodeURIComponent(source);

  var article = document.getElementById('main-content');
  if (!article) return;

  var editor = null;
  var original = '';

  var style = document.createElement('style');
  style.textContent = [
    '.linny-edit-bar{display:flex;gap:.6rem;align-items:center}',
    '.linny-edit-bar button{cursor:pointer;font:inherit;background:transparent;color:inherit}',
    '.linny-edit-bar .linny-icon-btn{display:inline-flex;align-items:center;border:0;padding:0;opacity:.7}',
    '.linny-edit-bar .linny-icon-btn:hover{opacity:1}',
    '.linny-edit-bar .linny-text-btn{font-size:.8rem;padding:.1rem .6rem;',
    'border:1px solid currentColor;border-radius:.25rem}',
    '.linny-edit-bar .linny-status{font-size:.75rem;opacity:.7}',
  ].join('');
  document.head.appendChild(style);

  var bar = document.createElement('div');
  bar.className = 'linny-edit-bar';

  function textButton(label) {
    var b = document.createElement('button');
    b.className = 'linny-text-btn';
    b.textContent = label;
    b.type = 'button';
    return b;
  }

  var editBtn = document.createElement('button');
  editBtn.className = 'linny-icon-btn';
  editBtn.type = 'button';
  editBtn.title = 'Edit this note';
  editBtn.setAttribute('aria-label', 'Edit this note');
  // Pencil. geekdoc's sprite has no pencil symbol (its own edit link reuses
  // gdoc_code), so this is inline; gdoc-icon gives it the theme's icon sizing.
  editBtn.innerHTML =
    '<svg class="gdoc-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">' +
    '<path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41' +
    'l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>';

  var saveBtn = textButton('Save');
  var cancelBtn = textButton('Cancel');
  var status = document.createElement('span');
  status.className = 'linny-status';

  saveBtn.hidden = true;
  cancelBtn.hidden = true;
  bar.append(status, saveBtn, cancelBtn, editBtn);

  var header = document.querySelector('.gdoc-page__header');
  if (header) {
    // The header is `justify-between` with the breadcrumb as its only child, so
    // appending puts the pencil at the right edge of that row. The theme hides
    // the whole row on mobile when it holds nothing clickable -- it does now.
    header.classList.remove('hidden-mobile');
    header.appendChild(bar);
  } else {
    article.before(bar);
  }

  function fail(what, err) {
    status.textContent = what + ' failed: ' + err;
  }

  function viewMode() {
    if (editor) editor.hidden = true;
    article.hidden = false;
    editBtn.hidden = false;
    saveBtn.hidden = true;
    cancelBtn.hidden = true;
  }

  function editMode(text) {
    if (!editor) {
      editor = document.createElement('textarea');
      editor.spellcheck = false;
      editor.style.cssText =
        'width:100%;min-height:70vh;font-family:ui-monospace,monospace;' +
        'font-size:.85rem;line-height:1.5;padding:.75rem;box-sizing:border-box';
      // Ctrl/Cmd+S is the reflex; don't let the browser hijack it.
      editor.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && e.key === 's') {
          e.preventDefault();
          save();
        }
      });
      article.after(editor);
    }
    original = text;
    editor.value = text;
    editor.hidden = false;
    article.hidden = true;
    editBtn.hidden = true;
    saveBtn.hidden = false;
    cancelBtn.hidden = false;
    status.textContent = '';
    // Assigning .value leaves the caret at the end of the text, so a plain
    // focus() scrolls the textarea to the bottom. Put the caret back at the
    // start first, then pin both the textarea and the page to the top.
    editor.setSelectionRange(0, 0);
    editor.focus({ preventScroll: true });
    editor.scrollTop = 0;
    bar.scrollIntoView({ block: 'start' });
  }

  /* Reload as soon as Hugo has re-rendered this page.
   *
   * A fixed timeout is a coin flip: --disableFastRender means a full rebuild,
   * which takes longer than any delay short enough to feel instant, and
   * reloading too early both shows the old page AND misses live-reload's
   * rebuild event (it fires while we are navigating). So compare the page as
   * the server rendered it before the save against what it serves now, and
   * reload the moment it differs.
   */
  function reloadWhenRebuilt(before) {
    var tries = 0;
    (function poll() {
      if (++tries > 60) return location.reload(); // ~30s; give up and show it
      setTimeout(function () {
        fetch(location.href, { cache: 'no-store' })
          .then(function (r) { return r.text(); })
          .then(function (now) {
            if (now !== before) location.reload();
            else poll();
          })
          .catch(poll);
      }, 500);
    })();
  }

  function save() {
    if (editor.value === original) return viewMode();
    saveBtn.disabled = true;
    status.textContent = 'Saving…';
    // Snapshot the pre-save render first, so the comparison above has a
    // baseline that is guaranteed to be the old one.
    fetch(location.href, { cache: 'no-store' })
      .then(function (r) { return r.text(); })
      .catch(function () { return null; })
      .then(function (before) {
        return fetch(url, {
          method: 'PUT',
          headers: { 'content-type': 'text/markdown; charset=utf-8' },
          body: editor.value,
        }).then(function (r) {
          if (!r.ok) return r.text().then(function (t) { throw new Error(t || r.status); });
          original = editor.value;
          status.textContent = 'Rebuilding…';
          viewMode();
          if (before === null) return location.reload();
          reloadWhenRebuilt(before);
        });
      })
      .catch(function (e) { fail('Save', e.message); })
      .finally(function () { saveBtn.disabled = false; });
  }

  editBtn.addEventListener('click', function () {
    editBtn.disabled = true;
    status.textContent = 'Loading source…';
    fetch(url)
      .then(function (r) {
        if (!r.ok) return r.text().then(function (t) { throw new Error(t || r.status); });
        return r.text();
      })
      .then(editMode)
      .catch(function (e) { fail('Load', e.message + ' — is edit-server.py running?'); })
      .finally(function () { editBtn.disabled = false; });
  });

  saveBtn.addEventListener('click', save);

  cancelBtn.addEventListener('click', function () {
    if (editor.value !== original && !confirm('Discard your changes?')) return;
    status.textContent = '';
    viewMode();
  });
})();
