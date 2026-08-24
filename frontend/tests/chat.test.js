// Chat-input behaviour, run against a production build.
//
//   npm run build && npx next start -p 3100 &
//   node tests/chat.test.js
//
// The /chat call is stubbed, so this exercises the UI without hitting Bedrock.
// Covers Enter-to-send / Shift+Enter-for-newline, the reader's name and its
// initials chip, and the top nav fitting once the name field is added to it.
const { chromium } = require('playwright');
const os = require('os');
const path = require('path');
const B='http://localhost:3100';
let pass=0,fail=0;
const ok=(n,c,x='')=>{c?(pass++,console.log(`  PASS  ${n}`)):(fail++,console.log(`  FAIL  ${n} ${x}`))};

(async () => {
  const b = await chromium.launch();
  // Stub the API so we test the UI, not Bedrock.
  const mk = async (locale='en-US') => {
    const ctx = await b.newContext({ viewport:{width:1280,height:900}, locale });
    await ctx.route('**/chat', r => r.fulfill({ status:200, contentType:'application/json', body: JSON.stringify({reply:'ok'}) }));
    const p = await ctx.newPage();
    return { ctx, p };
  };

  console.log('\n=== 1. Shift+Enter inserts a newline, does NOT send ===');
  let { ctx, p } = await mk();
  await p.goto(`${B}/en/avatar`, { waitUntil:'networkidle' });
  const ta = 'textarea';
  const before = await p.$$eval('.avatar-msg-row', n=>n.length);
  await p.click(ta);
  await p.type(ta, 'line one');
  const h1 = await p.$eval(ta, e=>e.clientHeight);
  await p.keyboard.press('Shift+Enter');
  await p.type(ta, 'line two');
  const val = await p.$eval(ta, e=>e.value);
  ok('newline inserted in the textarea', val === 'line one\nline two', JSON.stringify(val));
  ok('no message was sent', (await p.$$eval('.avatar-msg-row', n=>n.length)) === before);
  const h2 = await p.$eval(ta, e=>e.clientHeight);
  ok('textarea grew for the 2nd line', h2 > h1, `${h1} -> ${h2}`);

  console.log('\n=== 2. Enter sends, and the newline survives in the bubble ===');
  await p.keyboard.press('Enter');
  await p.waitForTimeout(600);
  ok('message sent', (await p.$$eval('.avatar-msg-row', n=>n.length)) > before);
  const bubble = await p.$$eval('.avatar-message-bubble', els => {
    const e = els[els.length-2]; return { text: e.innerText, ws: getComputedStyle(e).whiteSpace };
  });
  ok('both lines preserved', bubble.text.includes('line one') && bubble.text.includes('line two'));
  ok('rendered as two lines (pre-wrap)', bubble.ws === 'pre-wrap', bubble.ws);
  ok('textarea reset to one row', (await p.$eval(ta, e=>e.clientHeight)) <= h1 + 2);
  await ctx.close();

  console.log('\n=== 3. Name: defaults to "You", switches to initials ===');
  ({ ctx, p } = await mk());
  await p.goto(`${B}/en/avatar`, { waitUntil:'networkidle' });
  await p.fill('textarea', 'hi'); await p.keyboard.press('Enter'); await p.waitForTimeout(500);
  ok('chip shows "You" with no name', (await p.$eval('.avatar-user-chip', e=>e.textContent.trim())) === 'You');
  await p.fill('.avatar-name-input', 'Muhammad Salman');
  await p.waitForTimeout(300);
  ok('chip shows initials MS', (await p.$eval('.avatar-user-chip', e=>e.textContent.trim())) === 'MS');
  ok('full name in the tooltip', (await p.$eval('.avatar-user-chip', e=>e.title)) === 'Muhammad Salman');
  await p.fill('.avatar-name-input', 'Salman'); await p.waitForTimeout(200);
  ok('single word -> first two letters (SA)', (await p.$eval('.avatar-user-chip', e=>e.textContent.trim())) === 'SA');

  console.log('\n=== 4. Name persists across reload ===');
  await p.reload({ waitUntil:'networkidle' });
  await p.waitForTimeout(700);
  ok('name restored into the field', (await p.$eval('.avatar-name-input', e=>e.value)) === 'Salman');
  await p.fill('.avatar-name-input', ''); await p.waitForTimeout(200);
  await p.reload({ waitUntil:'networkidle' }); await p.waitForTimeout(700);
  ok('clearing the name forgets it', (await p.$eval('.avatar-name-input', e=>e.value)) === '');
  await ctx.close();

  console.log('\n=== 5. German locale ===');
  ({ ctx, p } = await mk('de-DE'));
  await p.goto(`${B}/de/avatar`, { waitUntil:'networkidle' });
  ok('name placeholder translated', (await p.$eval('.avatar-name-input', e=>e.placeholder)) === 'Dein Name / Initialen');
  await p.fill('textarea', 'hallo'); await p.keyboard.press('Enter'); await p.waitForTimeout(500);
  ok('chip shows "Du"', (await p.$eval('.avatar-user-chip', e=>e.textContent.trim())) === 'Du');
  ok('hint translated', (await p.$eval('.avatar-kbd-hint', e=>e.innerText)).includes('zum Senden'));
  await ctx.close();

  console.log('\n=== 6. Layout: nothing overflows, hint hidden on mobile ===');
  for (const vp of [{w:1280,h:900,n:'desktop'},{w:390,h:844,n:'iPhone 12'},{w:320,h:568,n:'iPhone SE'}]) {
    const c = await b.newContext({ viewport:{width:vp.w,height:vp.h}, locale:'de-DE' });
    const pg = await c.newPage();
    await pg.goto(`${B}/de/avatar`, { waitUntil:'networkidle' });
    await pg.waitForTimeout(400);
    const over = await pg.evaluate(()=>document.documentElement.scrollWidth > document.documentElement.clientWidth);
    const nav = await pg.evaluate(()=>{ const n=document.querySelector('.avatar-topnav');
      return [...n.children].every(c=>c.getBoundingClientRect().right <= n.getBoundingClientRect().right+1); });
    const hint = await pg.isVisible('.avatar-kbd-hint').catch(()=>false);
    ok(`${vp.n}: no horizontal overflow`, !over);
    ok(`${vp.n}: top nav contents fit`, nav);
    ok(`${vp.n}: hint ${vp.w<=768?'hidden':'shown'}`, vp.w<=768 ? !hint : hint);
    if (vp.n!=='desktop') await pg.screenshot({ path: path.join(os.tmpdir(), `shot-chat-${vp.w}.png`) });
    else await pg.screenshot({ path: path.join(os.tmpdir(), 'shot-chat-desktop.png') });
    await c.close();
  }

  await b.close();
  console.log(`\n================  ${pass} passed, ${fail} failed  ================`);
  process.exit(fail?1:0);
})();
