// End-to-end check of 心动匹配 against the real Go API and the Flutter web build.
// Prerequisites match the other suites: Go on QA_API_URL with
// ALLOWED_ORIGIN=http://localhost:8090, `node scripts/preview.cjs` on QA_APP_URL.
// Every identity below is created for this run inside a unique campus.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const apiOrigin = process.env.QA_API_URL || 'http://localhost:8081';
const appOrigin = process.env.QA_APP_URL || 'http://localhost:8090';
const artifacts = path.resolve(__dirname, '../artifacts');
const stamp = String(Date.now()).slice(-8);
const campus = `心动联测${stamp}`;
const videoHost = 'd8j0ntlcm91z4.cloudfront.net';

fs.mkdirSync(artifacts, { recursive: true });

async function api(method, route, token, data) {
  const response = await fetch(`${apiOrigin}/api/v1${route}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  const payload = response.status === 204 ? null : await response.json();
  assert(response.ok, `${method} ${route}: ${response.status} ${JSON.stringify(payload)}`);
  return payload;
}

async function revealFlutter(page) {
  await page.goto(appOrigin, { waitUntil: 'domcontentloaded' });
  await page.locator('flutter-view').waitFor();
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) await placeholder.first().evaluate((node) => node.click());
  await page.getByRole('group', { name: 'sayAnything', exact: true }).waitFor();
}

async function shot(page, name) {
  await page.mouse.move(0, 0);
  await page.waitForTimeout(350);
  await page.screenshot({ path: path.join(artifacts, `discover-${name}.png`) });
}

async function poll(check, message, timeout = 18000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await check();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  assert.fail(message);
}

async function back(page) {
  const button = page.getByRole('button', { name: /返回|Back/ }).first();
  await button.waitFor();
  await button.click();
  await page.waitForTimeout(350);
}

async function fillFlutter(locator, value) {
  await locator.click();
  await locator.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await locator.pressSequentially(value, { delay: 8 });
  await locator.press('Tab');
}

// Flutter merges a whole card into one labelled group, so copy can live in a
// text node or only in an aria-label, and chat bubbles prefix their text with
// the speaker ("我：…"). Accept a substring in either place.
function see(page, text) {
  return page
    .getByText(text)
    .or(page.locator(`flt-semantics[aria-label*="${text}"]`))
    .first();
}

async function absent(page, text) {
  const textNodes = await page.getByText(text, { exact: true }).count();
  const labelled = await page.locator(`flt-semantics[aria-label*="${text}"]`).count();
  return textNodes + labelled === 0;
}

// Choice bars expose buttons, chips expose checkboxes, plain labels expose text.
async function pick(page, name) {
  for (const role of ['button', 'checkbox']) {
    const control = page.getByRole(role, { name, exact: true });
    if (await control.count()) {
      await control.first().click();
      return;
    }
  }
  await page.getByText(name, { exact: true }).first().click();
}

async function assertNavigation(page) {
  for (const name of ['动态', '心动', '聊天', '附近', '我']) {
    await page.getByRole('button', { name, exact: true }).waitFor({ state: 'visible' });
  }
}

function swipeResponse(page) {
  return page.waitForResponse(
    (response) => /\/api\/v1\/discover\/[^/]+\/swipe$/.test(response.url()) && response.request().method() === 'POST',
  );
}

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const pageErrors = [];
  const consoleErrors = [];
  let page;
  try {
    page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    page.setDefaultTimeout(18000);
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    await page.route(`https://${videoHost}/**`, (route) => route.abort('failed'));

    // Seed one dealable peer and one peer who refuses private messages.
    const cardPeer = await api('POST', '/session', null, { campus });
    await api('PATCH', '/me', cardPeer.token, {
      alias: '卡片同学',
      gender: 'male',
      bio: '跑步、吉他、偶尔发呆。',
      grade: 'sophomore',
      tags: ['运动', '音乐'],
    });
    const quietPeer = await api('POST', '/session', null, { campus });
    await api('PATCH', '/me', quietPeer.token, { alias: '关闭私聊的同学', allowDM: false });

    await revealFlutter(page);
    await page.getByRole('textbox', { name: '你在哪所学校？' }).waitFor();
    await fillFlutter(page.getByRole('textbox', { name: '你在哪所学校？' }), campus);
    await page.getByRole('checkbox').click();
    await poll(async () => (await page.getByRole('checkbox').getAttribute('aria-checked')) === 'true', 'consent not checked');
    const sessionResponse = page.waitForResponse(
      (response) => response.url().endsWith('/api/v1/session') && response.request().method() === 'POST',
    );
    await page.getByRole('button', { name: '进入校园', exact: true }).click();
    const me = await (await sessionResponse).json();
    await page.getByText('校园里的声音', { exact: true }).waitFor({ timeout: 25000 });
    await assertNavigation(page);

    // Deck: the dealable peer shows as one card with bio, grade and tags; the DM-off peer never appears.
    await page.getByRole('button', { name: '心动', exact: true }).click();
    await page.getByText('心动匹配', { exact: true }).waitFor();
    await page.getByText('今日剩余 50 次心动', { exact: true }).waitFor();
    const card = page.getByRole('group', { name: /^卡片同学/ });
    await card.waitFor();
    const cardLabel = await card.getAttribute('aria-label');
    assert.match(cardLabel, /大二/, `card should show the grade: ${cardLabel}`);
    assert.match(cardLabel, /跑步、吉他、偶尔发呆。/, `card should show the bio: ${cardLabel}`);
    assert.match(cardLabel, new RegExp(campus), `card should name the campus: ${cardLabel}`);
    for (const tag of ['运动', '音乐']) {
      assert((await page.getByRole('checkbox', { name: tag, exact: true }).count()) >= 1, `tag ${tag} must be visible on the card`);
    }
    assert(await absent(page, '关闭私聊的同学'), 'a peer with private messages off must not be dealt');
    await shot(page, 'deck');

    // Like from the deck: no match yet, the quota drops, the deck empties.
    let swipe = swipeResponse(page);
    await page.getByRole('button', { name: '喜欢', exact: true }).click();
    let result = await (await swipe).json();
    assert.equal(result.matched, false, 'a one-sided like must not match');
    await see(page, '这会儿没有新的同学了').waitFor();
    await page.getByText('今日剩余 49 次心动', { exact: true }).waitFor();
    await shot(page, 'empty');
    assert.equal((await api('GET', '/discover', cardPeer.token)).likesMe, 1, 'the liked peer should see one admirer');

    // A second peer likes me first; a refresh deals them with priority.
    const liker = await api('POST', '/session', null, { campus });
    await api('PATCH', '/me', liker.token, {
      alias: '先心动的同学',
      gender: 'female',
      bio: '晚上常在图书馆三楼，喜欢安静的人。',
      grade: 'junior',
      tags: ['音乐', '电影'],
    });
    assert.equal((await api('POST', `/discover/${me.user.id}/swipe`, liker.token, { action: 'like' })).matched, false);
    await page.getByRole('button', { name: '刷新心动', exact: true }).click();
    const likerCard = page.getByRole('group', { name: /^先心动的同学/ });
    await likerCard.waitFor();
    assert.match(await likerCard.getAttribute('aria-label'), /晚上常在图书馆三楼，喜欢安静的人。/);
    await shot(page, 'liker-card');

    // Answer from 喜欢我的人: mutual like opens the match dialog, then the real chat.
    // The unread badge joins the accessible name ("喜欢我的人 1"), so match the prefix.
    const admirers = page.getByRole('button', { name: /^喜欢我的人/ });
    assert.match(await admirers.getAttribute('aria-label') ?? (await admirers.innerText()), /1/, 'badge should count one admirer');
    await admirers.click();
    await see(page, '他们先向你心动了。回应喜欢，就能开始聊天。').waitFor();
    await see(page, '先心动的同学').waitFor();
    await shot(page, 'likes');
    swipe = swipeResponse(page);
    await page.getByRole('button', { name: '喜欢', exact: true }).first().click();
    result = await (await swipe).json();
    assert.equal(result.matched, true, 'answering an admirer must match');
    assert.equal(typeof result.conversation?.id, 'string', 'a match must carry its conversation');
    await see(page, '心动了').waitFor();
    await see(page, '你和“先心动的同学”互相喜欢，可以开始聊天了。').waitFor();
    await shot(page, 'match');
    await page.getByRole('button', { name: '去聊天', exact: true }).click();
    await page.getByRole('textbox', { name: '输入消息…' }).waitFor();
    const firstLine = `互相心动之后的第一句话 ${stamp}`;
    await fillFlutter(page.getByRole('textbox'), firstLine);
    await page.getByRole('button', { name: '发送消息' }).click();
    await see(page, firstLine).waitFor();
    await shot(page, 'chat');

    const likerConversations = await api('GET', '/conversations', liker.token);
    assert.equal(likerConversations.length, 1, 'the match must be an ordinary conversation for the other side');
    assert.equal(likerConversations[0].id, result.conversation.id);
    assert.equal(likerConversations[0].lastMessage, firstLine);
    assert.equal(likerConversations[0].unread, 1);
    const likerMatches = await api('GET', '/discover/matches', liker.token);
    assert.equal(likerMatches.length, 1);
    assert.equal(likerMatches[0].conversationId, result.conversation.id);

    // The answered admirer leaves 喜欢我的人; 配对 lists them; the deck re-reads the quota.
    await back(page);
    await see(page, '这里还很安静').waitFor();
    await back(page);
    await page.getByText('心动匹配', { exact: true }).waitFor();
    await page.getByRole('button', { name: '配对', exact: true }).click();
    await see(page, '互相喜欢的人，都在这里。').waitFor();
    await see(page, '先心动的同学').waitFor();
    // The match row merges name and time into one node ("先心动的同学 互相心动 · 刚刚").
    await page
      .locator('flt-semantics[aria-label*="互相心动 · "]')
      .or(page.getByText(/互相心动 · /))
      .first()
      .waitFor();
    await shot(page, 'matches');
    await back(page);
    await page.getByText('心动匹配', { exact: true }).waitFor();
    try {
      await page.getByText('今日剩余 48 次心动', { exact: true }).waitFor({ timeout: 6000 });
    } catch {
      await page.getByRole('button', { name: '刷新心动', exact: true }).click();
      await page.getByText('今日剩余 48 次心动', { exact: true }).waitFor();
    }

    // Profile card fields under 我 reach the server and the peers who still see my card.
    await page.getByRole('button', { name: '我', exact: true }).click();
    await see(page, '心动资料').waitFor();
    await page.getByRole('button', { name: /^简介/ }).click();
    await see(page, '一句话简介').waitFor();
    const bio = `在天台看晚霞的人 ${stamp}`;
    await fillFlutter(page.getByRole('textbox'), bio);
    await page.getByRole('button', { name: '保存', exact: true }).click();
    await page.locator('flt-semantics').getByText('简介已更新', { exact: true }).waitFor();
    await page.getByRole('button', { name: /^年级/ }).click();
    await see(page, '只展示你选择的资料，也可以不填写。').waitFor();
    await pick(page, '大二');
    await page.locator('flt-semantics').getByText('年级资料已更新', { exact: true }).waitFor();
    await page.getByRole('button', { name: /^标签/ }).click();
    await see(page, '兴趣标签').waitFor();
    await pick(page, '阅读');
    await pick(page, '摄影');
    await see(page, '已选 2 / 5').waitFor();
    await page.getByRole('button', { name: '保存', exact: true }).click();
    await page.locator('flt-semantics').getByText('标签已更新', { exact: true }).waitFor();
    await see(page, bio).waitFor();
    await shot(page, 'profile');

    const meNow = await api('GET', '/me', me.token);
    assert.equal(meNow.bio, bio);
    assert.equal(meNow.grade, 'sophomore');
    assert.deepEqual(meNow.tags, ['阅读', '摄影']);
    const myCard = (await api('GET', '/discover', cardPeer.token)).items.find((item) => item.id === me.user.id);
    assert(myCard, 'the unanswered peer should still be dealt my card');
    assert.equal(myCard.bio, bio);
    assert.equal(myCard.grade, 'sophomore');
    assert.deepEqual(myCard.tags, ['阅读', '摄影']);
    assert.equal(myCard.distanceLabel, undefined, 'no distance without shared nearby locations');

    assert.deepEqual(pageErrors, [], `page errors: ${pageErrors.join('\n')}`);
    const unexpectedConsoleErrors = consoleErrors.filter(
      (message) => !message.includes('Failed to load resource: net::ERR_FAILED'),
    );
    assert.deepEqual(unexpectedConsoleErrors, [], `console errors: ${unexpectedConsoleErrors.join('\n')}`);
    console.log(`PASS discover: ${campus}; deck card with bio/grade/tags, DM-off peer hidden, one-sided like (50→49), liker dealt first, 喜欢我 answer → match dialog → chat delivered to the other side, 配对 list, quota re-read (48), 简介/年级/标签 edits visible to peers.`);
  } catch (error) {
    if (page) {
      try {
        await page.screenshot({ path: path.join(artifacts, 'discover-failure.png') });
        const labels = await page.evaluate(() =>
          [...document.querySelectorAll('flt-semantics')]
            .map((node) => node.getAttribute('aria-label') || node.textContent)
            .filter(Boolean),
        );
        fs.writeFileSync(path.join(artifacts, 'discover-failure.txt'), labels.join('\n'));
      } catch {
        /* keep the original failure */
      }
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
