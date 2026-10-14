// QA for the generated hero background video on the live site.
// Usage: SITE_URL=http://127.0.0.1:8085 node landing-video/qa/hero-video.cjs
// Requires the root devDependency `playwright` (channel: chrome).
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');

const origin = process.env.SITE_URL || 'http://127.0.0.1:8085';
const dir = path.resolve(__dirname, '../../artifacts');
fs.mkdirSync(dir, { recursive: true });

const videoState = (page) =>
  page.evaluate(() => {
    const v = document.querySelector('.hero-video');
    if (!v) return null;
    return {
      readyState: v.readyState,
      paused: v.paused,
      currentTime: v.currentTime,
      display: getComputedStyle(v).display,
      autoplay: v.hasAttribute('autoplay'),
      error: v.error ? v.error.code : null,
    };
  });

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const results = [];
  try {
    for (const [name, viewport] of [
      ['desktop', { width: 1440, height: 900 }],
      ['mobile', { width: 390, height: 844 }],
    ]) {
      const page = await browser.newPage({ viewport, deviceScaleFactor: 1 });
      const errors = [];
      page.on('pageerror', (e) => errors.push(e.message));
      await page.goto(origin, { waitUntil: 'load' });

      assert.equal(await page.locator('.hero-video').count(), 1, `${name}: .hero-video exists`);
      assert(
        await page.locator('.hero-photo').evaluate((e) => e.complete && e.naturalWidth >= 1600),
        `${name}: fallback hero photo still loads`
      );
      await page.waitForFunction(
        () => {
          const v = document.querySelector('.hero-video');
          return v && v.readyState >= 2;
        },
        null,
        { timeout: 10000 }
      );
      await page.waitForFunction(
        () => {
          const v = document.querySelector('.hero-video');
          return v && !v.paused && v.currentTime > 0;
        },
        null,
        { timeout: 10000 }
      );
      const a = await videoState(page);
      await page.waitForTimeout(800);
      const b = await videoState(page);
      assert(a.readyState >= 2, `${name}: readyState >= 2 (got ${a.readyState})`);
      assert.equal(b.paused, false, `${name}: video is playing`);
      assert(b.currentTime > a.currentTime, `${name}: currentTime advances (${a.currentTime} -> ${b.currentTime})`);
      assert.equal(b.display, 'block', `${name}: video displayed`);
      assert.equal(
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
        `${name}: no horizontal overflow`
      );
      await page.waitForTimeout(1200);
      await page.screenshot({ path: path.join(dir, `hero-video-${name}.png`) });

      // Scrolling the hero out of view must pause the video; scrolling back resumes it.
      await page.evaluate(() => scrollTo(0, document.documentElement.scrollHeight));
      await page.waitForFunction(() => document.querySelector('.hero-video').paused, null, { timeout: 5000 });
      await page.evaluate(() => scrollTo(0, 0));
      await page.waitForFunction(() => !document.querySelector('.hero-video').paused, null, { timeout: 5000 });

      // Reduced motion: CSS hides the video and the script keeps it from playing.
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.reload({ waitUntil: 'load' });
      await page.waitForTimeout(1000);
      const rm = await videoState(page);
      assert.equal(rm.display, 'none', `${name}: reduced motion hides the video`);
      assert.equal(rm.paused, true, `${name}: reduced motion keeps the video paused`);
      assert.equal(rm.autoplay, false, `${name}: reduced motion removes autoplay`);
      assert(
        await page.locator('.hero-photo').evaluate((e) => e.complete && e.naturalWidth >= 1600),
        `${name}: photo visible under reduced motion`
      );
      assert.deepEqual(errors, [], `${name}: no page errors`);
      results.push(`${name} ${viewport.width}x${viewport.height}: readyState=${a.readyState}, playing, t ${a.currentTime.toFixed(2)}→${b.currentTime.toFixed(2)}, reduced-motion display=${rm.display} paused=${rm.paused}`);
      await page.close();
    }

    for (const width of [360, 390]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      await page.goto(origin, { waitUntil: 'load' });
      await page.waitForTimeout(500);
      assert.equal(
        await page.evaluate(() => document.documentElement.scrollWidth > innerWidth),
        false,
        `no horizontal overflow at ${width}`
      );
      results.push(`${width}px: no horizontal overflow`);
      await page.close();
    }

    const head = await fetch(origin + '/assets/video/hero-loop.mp4', { method: 'HEAD' });
    assert.equal(head.status, 200, 'mp4 served');
    results.push(`mp4 HEAD 200, content-type=${head.headers.get('content-type')}, bytes=${head.headers.get('content-length')}, accept-ranges=${head.headers.get('accept-ranges')}`);

    console.log('PASS hero video QA\n- ' + results.join('\n- '));
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
