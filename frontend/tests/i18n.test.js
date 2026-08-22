// End-to-end i18n checks, run against a production build.
//
//   npm run build && npx next start -p 3100 &
//   node tests/i18n.test.js
//
// Covers the parts of the two-language setup that only fail in a real browser:
// the language hint is gated on navigator.language and localStorage, and the
// banner renders nothing until after mount, so nothing here is visible to a
// static check of the built HTML. i18n-sweep.js is the companion: it diffs all
// visible text between /en and /de to catch strings that were never translated.
const { chromium } = require('playwright');
const B = 'http://localhost:3100';
let pass = 0, fail = 0;
const ok = (n, c, extra='') => { c ? (pass++, console.log(`  PASS  ${n}`)) : (fail++, console.log(`  FAIL  ${n} ${extra}`)); };

(async () => {
  const browser = await chromium.launch();

  // Collect console errors / page errors for every page we open.
  const errs = [];
  const newCtx = async (opts) => {
    const ctx = await browser.newContext(opts);
    ctx.on('weberror', e => errs.push(String(e.error())));
    return ctx;
  };
  const newPage = async (ctx, label) => {
    const p = await ctx.newPage();
    p.on('console', m => { if (m.type() === 'error') errs.push(`[${label}] console: ${m.text()}`); });
    p.on('pageerror', e => errs.push(`[${label}] pageerror: ${e.message}`));
    return p;
  };

  const HINT = '.lang-hint';

  console.log('\n=== 1. German browser on /en -> banner appears, in German ===');
  let ctx = await newCtx({ locale: 'de-DE' });
  let page = await newPage(ctx, 'de-on-en');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForSelector(HINT, { timeout: 5000 }).catch(() => {});
  ok('banner visible', await page.isVisible(HINT).catch(() => false));
  const text = await page.textContent(HINT).catch(() => '');
  ok('banner text is German', text.includes('Diese Seite gibt es auch auf Deutsch'), `got: ${text}`);
  const href = await page.getAttribute('.lang-hint-cta', 'href');
  ok('CTA points at /de', href === '/de', `got: ${href}`);
  await page.screenshot({ path: 'shot-01-de-browser-on-en.png' });

  console.log('\n=== 2. Clicking the CTA navigates to /de and shows German ===');
  await page.click('.lang-hint-cta');
  await page.waitForURL('**/de', { timeout: 5000 });
  ok('url is /de', new URL(page.url()).pathname === '/de', page.url());
  ok('html lang=de', (await page.getAttribute('html', 'lang')) === 'de');
  const body = await page.evaluate(() => document.body.innerText);
  ok('German copy rendered', body.includes('Ich bin Salmans') && body.includes('Frag mich alles'));
  ok('no visible English leak', !body.includes('Ask me anything') && !body.includes('Munich, Germany'), body.slice(0,200));
  ok('banner gone on /de', !(await page.isVisible(HINT).catch(() => false)));
  await page.screenshot({ path: 'shot-02-de-page.png' });
  await ctx.close();

  console.log('\n=== 3. Dismiss (x) persists across reload ===');
  ctx = await newCtx({ locale: 'de-DE' });
  page = await newPage(ctx, 'dismiss');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForSelector(HINT, { timeout: 5000 });
  await page.click('.lang-hint-close');
  ok('hidden right after dismiss', !(await page.isVisible(HINT).catch(() => false)));
  const ls = await page.evaluate(() => localStorage.getItem('lang-hint-dismissed'));
  ok('localStorage flag set', ls === '1', `got: ${ls}`);
  await page.reload({ waitUntil: 'networkidle' });
  await page.waitForTimeout(600);
  ok('still hidden after reload', !(await page.isVisible(HINT).catch(() => false)));
  await ctx.close();

  console.log('\n=== 4. Clicking the CTA also counts as dismissal ===');
  ctx = await newCtx({ locale: 'de-DE' });
  page = await newPage(ctx, 'cta-dismiss');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForSelector(HINT, { timeout: 5000 });
  await page.click('.lang-hint-cta');
  await page.waitForURL('**/de');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(600);
  ok('banner does not return on /en', !(await page.isVisible(HINT).catch(() => false)));
  await ctx.close();

  console.log('\n=== 5. English browser on /en -> no banner ===');
  ctx = await newCtx({ locale: 'en-US' });
  page = await newPage(ctx, 'en-on-en');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);
  ok('no banner', !(await page.isVisible(HINT).catch(() => false)));
  await ctx.close();

  console.log('\n=== 6. English browser on /de -> English banner offered ===');
  ctx = await newCtx({ locale: 'en-US' });
  page = await newPage(ctx, 'en-on-de');
  await page.goto(`${B}/de`, { waitUntil: 'networkidle' });
  await page.waitForSelector(HINT, { timeout: 5000 }).catch(() => {});
  ok('banner visible', await page.isVisible(HINT).catch(() => false));
  const t6 = await page.textContent(HINT).catch(() => '');
  ok('text is English', t6.includes('This page is also available in English'), `got: ${t6}`);
  ok('CTA points at /en', (await page.getAttribute('.lang-hint-cta', 'href')) === '/en');
  await page.screenshot({ path: 'shot-06-en-browser-on-de.png' });
  await ctx.close();

  console.log('\n=== 7. de-AT matches de; "den" (Dendi) must not ===');
  ctx = await newCtx({ locale: 'de-AT' });
  page = await newPage(ctx, 'de-AT');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForSelector(HINT, { timeout: 5000 }).catch(() => {});
  ok('de-AT gets the banner', await page.isVisible(HINT).catch(() => false));
  await ctx.close();

  ctx = await newCtx({ locale: 'den' });
  page = await newPage(ctx, 'den');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);
  ok('"den" does NOT get the banner', !(await page.isVisible(HINT).catch(() => false)));
  await ctx.close();

  console.log('\n=== 8. Chat page has no banner (fixed input bar) ===');
  ctx = await newCtx({ locale: 'de-DE' });
  page = await newPage(ctx, 'avatar');
  await page.goto(`${B}/en/avatar`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(800);
  ok('no banner on /en/avatar', !(await page.isVisible(HINT).catch(() => false)));
  await ctx.close();

  console.log('\n=== 9. Language toggle keeps you on the same page ===');
  ctx = await newCtx({ locale: 'en-US' });
  page = await newPage(ctx, 'toggle');
  await page.goto(`${B}/de/avatar`, { waitUntil: 'networkidle' });
  const tog = await page.getAttribute('a[href="/en/avatar"][title]', 'href').catch(() => null);
  ok('/de/avatar toggle -> /en/avatar', tog === '/en/avatar', `got: ${tog}`);
  await ctx.close();

  console.log('\n=== 10. Mobile viewport: banner does not cover the CTA button ===');
  ctx = await newCtx({ locale: 'de-DE', viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  page = await newPage(ctx, 'mobile');
  await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
  await page.waitForSelector(HINT, { timeout: 5000 }).catch(() => {});
  const el = await page.$(HINT);
  const box = el ? await el.boundingBox() : null;
  ok('banner within viewport width', box && box.x >= 0 && box.x + box.width <= 390, JSON.stringify(box));
  await page.screenshot({ path: 'shot-10-mobile.png' });
  await ctx.close();

  console.log('\n=== 12. Locale toggle always lands at the top of the page ===');
  // Regression: switching locale swaps the [lang] root layout, and Next's
  // soft-navigation scroll handler picked the wrong node for that case —
  // clicking DE from the top of /en dropped the reader ~6100px down, into the
  // footer. The toggle is a plain <a> for this reason; keep it that way.
  for (const start of [0, 2000, 5000]) {
    ctx = await newCtx({ viewport: { width: 1440, height: 900 } });
    page = await newPage(ctx, `scroll-${start}`);
    await page.goto(`${B}/en`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    if (start) { await page.evaluate((s) => window.scrollTo(0, s), start); await page.waitForTimeout(300); }
    await page.click('.lang-toggle');
    await page.waitForURL('**/de');
    await page.waitForTimeout(1000);
    const after = await page.evaluate(() => Math.round(window.scrollY));
    ok(`from scrollY=${start} -> lands at top`, after < 50, `landed at ${after}`);
    await ctx.close();
  }

  console.log('\n=== 11. No console errors / hydration mismatches anywhere ===');
  const hydration = errs.filter(e => /hydrat|did not match|Minified React error #41[08]/i.test(e));
  ok('no hydration errors', hydration.length === 0, JSON.stringify(hydration, null, 2));
  const real = errs.filter(e => !/favicon|404 \(Not Found\)/i.test(e));
  ok('no other console errors', real.length === 0, JSON.stringify(real, null, 2));

  await browser.close();
  console.log(`\n================  ${pass} passed, ${fail} failed  ================`);
  process.exit(fail ? 1 : 0);
})();
