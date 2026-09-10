const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const apiOrigin = process.env.QA_API_URL || 'http://localhost:8081';
const appOrigin = process.env.QA_APP_URL || 'http://localhost:8090';
const artifacts = path.resolve(__dirname, '../artifacts');
const imageFile = process.env.QA_IMAGE_PATH || path.resolve(__dirname, '../server/web/assets/campus-courtyard.webp');
const videoFile = process.env.QA_VIDEO_PATH || path.join(artifacts, 'media-fixtures', 'bee.mp4');
const campus = `媒体校园联测${String(Date.now()).slice(-8)}`;

assert(fs.existsSync(imageFile), `missing image fixture: ${imageFile}`);
assert(
  fs.existsSync(videoFile),
  `missing video fixture: ${videoFile}\nDownload the Flutter documentation sample from https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4 or set QA_VIDEO_PATH.`,
);

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

async function poll(check, message, timeout = 20000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await check();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  assert.fail(message);
}

async function revealFlutter(page) {
  await page.goto(appOrigin, { waitUntil: 'domcontentloaded' });
  await page.locator('flutter-view').waitFor({ timeout: 30000 });
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) await placeholder.first().evaluate((node) => node.click());
  await page.getByRole('group', { name: 'sayAnything', exact: true }).waitFor();
}

async function choose(page, files) {
  const button = page.getByRole('button', { name: '添加图片或视频', exact: true });
  await button.waitFor();
  const box = await button.boundingBox();
  assert(box, 'media add button has no layout box');
  const event = page.waitForEvent('filechooser');
  await button.evaluate((node) => node.click());
  await (await event).setFiles(files);
  await page.getByRole('button', { name: '移除附件 1', exact: true }).waitFor();
}

async function fillFlutter(locator, value) {
  await locator.click();
  await locator.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await locator.pressSequentially(value, { delay: 8 });
  await locator.press('Tab');
}

async function back(page) {
  await page
    .getByRole('button', { name: /返回|Back/ })
    .first()
    .evaluate((node) => node.click());
  await page.waitForTimeout(300);
}

async function shot(page, name) {
  await page.mouse.move(0, 0);
  await page.waitForTimeout(250);
  await page.screenshot({ path: path.join(artifacts, `media-${name}.png`) });
}

(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const pageErrors = [];
  const consoleErrors = [];
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    page.setDefaultTimeout(20000);
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    await page.route('https://d8j0ntlcm91z4.cloudfront.net/**', (route) =>
      route.abort('failed'),
    );

    await revealFlutter(page);
    await fillFlutter(page.getByRole('textbox', { name: '你在哪所学校？' }), campus);
    const consent = page.getByRole('checkbox');
    await consent.click();
    await poll(
      async () => (await consent.getAttribute('aria-checked')) === 'true',
      'consent checkbox did not stay checked',
      3000,
    );
    await page.getByRole('button', { name: '进入校园', exact: true }).click();
    await page.getByText('校园里的声音', { exact: true }).waitFor({ timeout: 30000 });

    const peer = await api('POST', '/session', null, { campus });
    await api('PATCH', '/me', peer.token, { alias: '媒体联测同学' });

    const postText = `图片视频联测 ${String(Date.now()).slice(-6)}`;
    await page.getByRole('button', { name: '说点什么', exact: true }).click();
    await fillFlutter(page.getByRole('textbox'), postText);
    await choose(page, [imageFile, videoFile]);
    await page.getByRole('button', { name: '移除附件 2', exact: true }).waitFor();
    await shot(page, 'draft-image-video');
    await page.getByRole('button', { name: '发布', exact: true }).click();

    const post = await poll(async () => {
      const posts = await api('GET', '/posts', peer.token);
      return posts.find((item) => item.body === postText && item.attachments?.length === 2);
    }, 'image+video post was not persisted');
    const image = post.attachments.find((item) => item.kind === 'image');
    const video = post.attachments.find((item) => item.kind === 'video');
    assert(image && video, 'post should contain one image and one video');

    for (const media of [image, video]) {
      const ticket = await api('POST', `/media/${media.id}/ticket`, peer.token, {});
      assert(!ticket.url.includes(peer.token), 'session token leaked into media URL');
      const response = await fetch(new URL(ticket.url, apiOrigin));
      assert.equal(response.status, 200, `peer could not read ${media.kind}`);
      assert(Number(response.headers.get('content-length') || 0) > 0, 'empty media response');
    }

    await page.mouse.move(195, 550);
    await page.mouse.wheel(0, 900);
    const postCard = page.getByRole('group', { name: new RegExp(postText) }).first();
    await postCard.waitFor();
    await shot(page, 'post');

    const imageButton = page.getByRole('button', { name: /查看图片/ }).first();
    await imageButton.click();
    await page.getByText(image.name, { exact: true }).waitFor();
    await shot(page, 'image-viewer');
    assert.equal(await page.getByRole('button', { name: '重新加载附件' }).count(), 0, 'image viewer showed an error');
    await back(page);

    const videoButton = page.getByRole('button', { name: /播放视频/ }).first();
    await videoButton.click();
    const play = page.getByRole('button', { name: '播放视频', exact: true });
    await play.waitFor({ timeout: 30000 });
    const element = page.locator('video').first();
    await element.waitFor({ timeout: 30000 });
    const initial = await element.evaluate((node) => ({ paused: node.paused, time: node.currentTime, duration: node.duration }));
    assert(initial.paused, 'video autoplayed');
    assert(Number.isFinite(initial.duration) && initial.duration > 0, 'video duration unavailable');
    await play.evaluate((node) => node.click());
    await poll(async () => (await element.evaluate((node) => node.currentTime)) > initial.time + 0.2, 'video time did not advance');
    await page.getByRole('button', { name: '暂停视频', exact: true }).waitFor();
    await shot(page, 'video-playing');
    await back(page);

    await postCard.click({ position: { x: 100, y: 70 } });
    await page.getByRole('button', { name: '发送评论' }).waitFor();
    const commentText = '评论图片附件';
    await fillFlutter(page.getByRole('textbox'), commentText);
    await choose(page, imageFile);
    await page.getByRole('button', { name: '发送评论' }).click();
    await poll(async () => {
      const comments = await api('GET', `/posts/${post.id}/comments`, peer.token);
      return comments.find((item) => item.body === commentText && item.attachments?.length === 1);
    }, 'comment image attachment was not persisted');
    await back(page);

    await page.mouse.move(195, 500);
    await page.mouse.wheel(0, -1200);
    await page.getByRole('button', { name: '话题房间', exact: true }).click();
    await page.getByRole('button', { name: /深夜树洞/ }).click();
    const roomText = '房间视频附件';
    await fillFlutter(page.getByRole('textbox', { name: '输入消息…' }), roomText);
    await choose(page, videoFile);
    await page.getByRole('button', { name: '发送消息' }).click();
    await poll(async () => {
      const messages = await api('GET', '/rooms/treehole/messages', peer.token);
      return messages.find((item) => item.body === roomText && item.attachments?.[0]?.kind === 'video');
    }, 'room video attachment was not persisted');
    await shot(page, 'room-video');
    await back(page);
    await back(page);

    await page.mouse.move(195, 500);
    await page.mouse.wheel(0, -1200);
    const peerPost = await api('POST', '/posts', peer.token, {
      body: '从这里发起媒体私聊',
      category: '校园日常',
      clientId: `peer-${Date.now()}`,
    });
    await page.getByRole('button', { name: '刷新广场' }).click();
    await page.mouse.move(195, 550);
    await page.mouse.wheel(0, 900);
    await page
      .getByRole('group', { name: /从这里发起媒体私聊/ })
      .click({ position: { x: 100, y: 70 } });
    await page.getByRole('button', { name: '悄悄打个招呼' }).click();
    await page.getByRole('textbox', { name: '输入消息…' }).waitFor();
    const dmText = '私聊图片附件';
    await fillFlutter(page.getByRole('textbox', { name: '输入消息…' }), dmText);
    await choose(page, imageFile);
    await page.getByRole('button', { name: '发送消息' }).click();
    const dm = await poll(async () => {
      const conversations = await api('GET', '/conversations', peer.token);
      const conversation = conversations.find((item) => item.lastMessage === dmText);
      if (!conversation) return null;
      const messages = await api('GET', `/conversations/${conversation.id}/messages`, peer.token);
      return messages.find((item) => item.body === dmText && item.attachments?.[0]?.kind === 'image');
    }, 'DM image attachment was not persisted');
    assert(dm.attachments.length === 1 && peerPost.id, 'DM media assertion failed');
    await shot(page, 'dm-image');

    assert.deepEqual(pageErrors, [], `page errors: ${pageErrors.join('\n')}`);
    const unexpectedConsole = consoleErrors.filter(
      (message) =>
        !message.includes('d8j0ntlcm91z4.cloudfront.net') &&
        !message.includes('Failed to load resource: net::ERR_FAILED'),
    );
    assert.deepEqual(unexpectedConsole, [], `console errors: ${unexpectedConsole.join('\n')}`);
    console.log(`PASS media E2E: ${campus}; chooser image+video, peer tickets, image viewer, real video playback, comment/room/DM attachments.`);
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
