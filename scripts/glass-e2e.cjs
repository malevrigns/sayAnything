const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const apiOrigin = process.env.QA_API_URL || 'http://localhost:8081';
const appOrigin = process.env.QA_APP_URL || 'http://localhost:8090';
const artifacts = path.resolve(__dirname, '../artifacts');
const campus = `玻璃校园联测${String(Date.now()).slice(-8)}`;
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
  await page.screenshot({ path: path.join(artifacts, `glass-${name}.png`) });
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
}

async function fillFlutter(locator, value) {
  await locator.click();
  await locator.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await locator.pressSequentially(value, { delay: 8 });
  await locator.press('Tab');
}

async function assertNoOverflow(page, width) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  assert.equal(overflow, false, `horizontal overflow at ${width}px`);
}

async function assertSingleColumn(page) {
  const nav = ['聊天', '记录', '设置'];
  const boxes = [];
  for (const name of nav) boxes.push(await page.getByRole('button', { name, exact: true }).boundingBox());
  assert(boxes.every(Boolean), 'all three navigation controls should be visible');
  const left = Math.min(...boxes.map((box) => box.x));
  const right = Math.max(...boxes.map((box) => box.x + box.width));
  assert(right - left <= 480, `desktop app content exceeded 480px (${right - left}px)`);
  assert(left >= (1440 - 520) / 2, `desktop app was not centered (${left}px)`);
}

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const pageErrors = [];
  const consoleErrors = [];
  let videoRequests = 0;
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    page.setDefaultTimeout(18000);
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    await page.route(`https://${videoHost}/**`, async (route) => {
      videoRequests++;
      await route.abort('failed');
    });

    await revealFlutter(page);
    if (videoRequests === 0) {
      await page.evaluate((url) => {
        const video = document.createElement('video');
        video.hidden = true;
        video.src = url;
        document.body.append(video);
        video.load();
      }, `https://${videoHost}/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260315_073750_51473149-4350-4920-ae24-c8214286f323.mp4`);
      await poll(() => videoRequests > 0, 'CloudFront video request was not intercepted', 3000);
    }
    await page.getByRole('textbox', { name: '你在哪所学校？' }).waitFor();
    await shot(page, 'welcome');
    assert(await page.getByText('校园匿名交流 · 无需公开身份', { exact: true }).isVisible());
    assertNoOverflow(page, 390);

    await fillFlutter(page.getByRole('textbox', { name: '你在哪所学校？' }), campus);
    await page.getByRole('checkbox').click();
    await poll(async () => await page.getByRole('checkbox').getAttribute('aria-checked') === 'true', 'consent not checked');
    await page.getByRole('button', { name: '进入校园', exact: true }).click();
    await page.getByText('校园里的声音', { exact: true }).waitFor({ timeout: 25000 });

    const other = await api('POST', '/session', null, { campus });
    const otherAlias = `晚风同学${String(Date.now()).slice(-4)}`;
    await api('PATCH', '/me', other.token, { alias: otherAlias });
    const postText = '路过操场时看见晚霞，想把这一刻分享给同校的人。';
    const post = await api('POST', '/posts', other.token, { body: postText, category: '校园日常' });

    await page.getByRole('button', { name: '刷新广场' }).click();
    const postCard = page.getByRole('group', { name: new RegExp(postText) });
    await postCard.waitFor();
    await shot(page, 'feed');
    await postCard.click({ position: { x: 100, y: 70 } });

    const comment = '我也看到了，今天的晚霞很安静。';
    await fillFlutter(page.getByRole('textbox'), comment);
    const commentButton = page.getByRole('button', { name: '发送评论' });
    await commentButton.waitFor({ state: 'visible' });
    assert(await commentButton.isEnabled(), 'comment button stayed disabled after input');
    await commentButton.click();
    await poll(async () => {
      const comments = await api('GET', `/posts/${post.id}/comments`, other.token);
      return comments.some((item) => item.body === comment);
    }, 'UI comment was not persisted');

    await page.getByRole('button', { name: '悄悄打个招呼' }).click();
    await poll(async () => {
      const items = await api('GET', '/conversations', other.token);
      return items[0];
    }, 'conversation was not created');
    await page.getByRole('textbox', { name: '输入消息…' }).waitFor();
    const firstDm = '你好，看到你的晚霞分享了。';
    await fillFlutter(page.getByRole('textbox'), firstDm);
    await page.getByRole('button', { name: '发送消息' }).click();
    const conversation = await poll(async () => {
      const conversations = await api('GET', '/conversations', other.token);
      return conversations.find((item) => item.lastMessage === firstDm);
    }, 'UI direct message was not persisted');
    assert(conversation, 'UI direct message was not persisted');
    const reply = '你好！很高兴有人也注意到了。';
    await api('POST', `/conversations/${conversation.id}/messages`, other.token, { body: reply });
    await page.getByRole('button', { name: '刷新对话' }).click();
    await page.waitForTimeout(800);
    await shot(page, 'chat');

    await back(page);
    await back(page);
    await page.getByRole('button', { name: '话题房间', exact: true }).click();
    await page.getByText('话题房间', { exact: true }).waitFor();
    await page.getByRole('button', { name: /深夜树洞/ }).waitFor();
    await shot(page, 'rooms');
    await page.getByRole('button', { name: /深夜树洞/ }).click();
    const roomMessage = '今晚先把烦恼放下，明天再继续努力。';
    await fillFlutter(page.getByRole('textbox'), roomMessage);
    await page.getByRole('button', { name: '发送消息' }).click();
    await poll(async () => {
      const roomMessages = await api('GET', '/rooms/treehole/messages', other.token);
      return roomMessages.some((item) => item.body === roomMessage);
    }, 'room message was not persisted');
    await back(page);
    await back(page);

    await page.getByRole('button', { name: '记录', exact: true }).click();
    await page.getByText('聊天记录', { exact: true }).waitFor();
    await page.getByRole('button', { name: new RegExp(otherAlias) }).waitFor();
    await shot(page, 'records');
    await page.getByRole('button', { name: '搜索聊天记录' }).click();
    const search = page.getByRole('textbox', { name: '搜索昵称或最近消息' });
    await fillFlutter(search, otherAlias.slice(0, 4));
    assert(await page.getByRole('button', { name: new RegExp(otherAlias) }).isVisible(), 'alias search failed');
    await fillFlutter(search, reply.slice(0, 5));
    assert(await page.getByRole('button', { name: new RegExp(reply) }).isVisible(), 'recent-message search failed');
    await back(page);

    await page.getByRole('button', { name: '设置', exact: true }).click();
    await page.getByRole('button', { name: /匿名昵称/ }).click();
    const nickname = `灰玻璃同学${String(Date.now()).slice(-3)}`;
    await fillFlutter(page.getByRole('textbox'), nickname);
    await page.getByRole('button', { name: '保存', exact: true }).click();
    await page.getByRole('button', { name: new RegExp(nickname) }).waitFor();
    const renameToast = page.locator('flt-semantics').getByText('昵称已更新', { exact: true });
    if (await renameToast.count()) {
      await renameToast.waitFor({ state: 'hidden', timeout: 8000 });
    }

    const dynamic = page.getByRole('switch', { name: /动态背景/ });
    if ((await dynamic.getAttribute('aria-checked')) === 'true') await dynamic.click();
    const reduced = page.getByRole('switch', { name: /减少动态效果/ });
    if ((await reduced.getAttribute('aria-checked')) !== 'true') await reduced.click();
    await shot(page, 'settings');

    await page.getByRole('button', { name: /文字大小/ }).click();
    await page.getByRole('button', { name: '大', exact: true }).click();
    await page.getByText('同时尊重设备的系统文字缩放设置。', { exact: true }).waitFor();
    await shot(page, 'size');
    await back(page);
    await page.getByRole('button', { name: /隐私与数据/ }).click();
    await page.getByText(/消息保存在你连接的校园服务端/).waitFor();
    await page.getByText(/私聊不是端到端加密/).waitFor();
    await back(page);

    for (const width of [360, 430]) {
      await page.setViewportSize({ width, height: 844 });
      await page.waitForTimeout(350); // Allow Flutter to publish the new frame and semantics.
      await assertNoOverflow(page, width);
      await shot(page, `${width}`);
    }
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.waitForTimeout(350);
    await assertNoOverflow(page, 1440);
    await assertSingleColumn(page);
    await shot(page, 'desktop');

    const visibleText = (await page.locator('flt-semantics').allTextContents()).join('\n');
    assert(!/AI助手|生成回复|停止生成|人工智能/i.test(visibleText), 'AI copy appeared in the human chat app');
    assert(videoRequests > 0, 'CloudFront video fallback was not exercised');
    assert.deepEqual(pageErrors, [], `page errors: ${pageErrors.join('\n')}`);
    const unexpectedConsoleErrors = consoleErrors.filter(
      (message) => !message.includes('Failed to load resource: net::ERR_FAILED'),
    );
    assert.deepEqual(unexpectedConsoleErrors, [], `console errors: ${unexpectedConsoleErrors.join('\n')}`);
    console.log(`PASS glass UI: ${campus}; fallback, real feed/comment/DM/room/search/settings/privacy, 390/360/430/1440.`);
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
