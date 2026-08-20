const { chromium } = require('playwright');

// Proper nouns / brand terms that are correctly identical in both languages.
const ALLOW = /^(PORTFOLIO|Digital Twin|Muhammad Salman|Salman|DE|EN|GitHub|LinkedIn|YouTube|Next\.js|AWS|Terraform|Kubernetes|Docker|Bedrock|~\/muhammad-salman:|[\d\W]*|.{0,2})$/i;

const grab = (p) => p.evaluate(() => {
  const out = [];
  const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (w.nextNode()) {
    const n = w.currentNode;
    if (n.parentElement.closest('script,style')) continue;
    const t = n.textContent.trim();
    if (t) out.push(t);
  }
  // attributes users can see / hear
  for (const el of document.querySelectorAll('[placeholder],[aria-label],[title],[alt]'))
    for (const a of ['placeholder','aria-label','title','alt'])
      if (el.hasAttribute(a)) out.push(`@${a}: ${el.getAttribute(a).trim()}`);
  return out;
});

(async () => {
  const b = await chromium.launch();
  for (const path of ['', '/avatar']) {
    const res = {};
    for (const loc of ['en','de']) {
      const ctx = await b.newContext({ viewport:{width:1280,height:900} });
      const p = await ctx.newPage();
      await p.goto(`http://localhost:3100/${loc}${path}`, { waitUntil:'networkidle' });
      await p.waitForTimeout(400);
      res[loc] = await grab(p);
      await ctx.close();
    }
    const de = new Set(res.de);
    const shared = res.en.filter(t => de.has(t) && !ALLOW.test(t));
    console.log(`\n=== /{lang}${path||''} — strings identical in EN and DE (possible untranslated) ===`);
    if (!shared.length) console.log('   none');
    for (const t of [...new Set(shared)]) console.log(`   • ${t.slice(0,90)}`);
  }
  await b.close();
})();
