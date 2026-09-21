'use strict';

const downloadLinks = {
  android: document.querySelector('#android-download'),
  windows: document.querySelector('#windows-download'),
};
const variantLinks = [...document.querySelectorAll('[data-download-platform]')];

for (const link of [...Object.values(downloadLinks), ...variantLinks]) {
  if (!link) continue;
  link.dataset.url = link.getAttribute('href');
  link.removeAttribute('href');
  link.setAttribute('aria-disabled', 'true');
}

function setDownload(link, available, url = link.dataset.url) {
  link.setAttribute('aria-disabled', String(!available));
  if (available) link.setAttribute('href', url);
  else link.removeAttribute('href');
}

async function checkDownloads() {
  const status = document.querySelector('#download-status');
  try {
    const response = await fetch('/api/downloads', { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('unavailable');
    const data = await response.json();
    const arm64 = data.androidArm64 === true;
    const android = arm64 || data.android === true;
    setDownload(
      downloadLinks.android,
      android,
      arm64 ? './downloads/sayanything-android-arm64.apk' : downloadLinks.android.dataset.url
    );
    setDownload(downloadLinks.windows, data.windows === true);
    downloadLinks.android.querySelector('small').textContent = android
      ? `${arm64 ? 'Android 64 位' : '安卓通用版'} · v1.4.1`
      : '安装包准备中';
    downloadLinks.windows.querySelector('small').textContent = data.windows
      ? 'Windows x64 · v1.4.1'
      : '安装包准备中';
    for (const link of variantLinks) {
      setDownload(link, data[link.dataset.downloadPlatform] === true);
    }
    status.textContent =
      android || data.windows
        ? '自签测试发行版。安装后，连接你的校园服务即可使用。'
        : '安装包准备中，发布后可在这里下载。';
  } catch {
    for (const link of Object.values(downloadLinks)) {
      if (link) link.querySelector('small').textContent = '暂时无法检查';
    }
    status.textContent = '暂时无法连接下载服务，请稍后刷新重试。';
  }
}

checkDownloads();

const menu = document.querySelector('#mobile-menu');
const nav = document.querySelector('#main-nav');
if (menu && nav) {
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('open', open);
  });
  nav.querySelectorAll('a').forEach((a) =>
    a.addEventListener('click', () => {
      nav.classList.remove('open');
      menu.setAttribute('aria-expanded', 'false');
    })
  );
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menu.getAttribute('aria-expanded') === 'true') {
      nav.classList.remove('open');
      menu.setAttribute('aria-expanded', 'false');
    }
  });
}

const views = {
  chat: {
    image: './assets/app-chat.png',
    alt: '说点什么匿名私聊的实际运行截图',
    title: '从「我也是」，到「说说看」。',
    body: '一条让你共鸣的声音，就是认识另一个人的开始。',
    count: '01',
  },
  rooms: {
    image: './assets/app-rooms.png',
    alt: '说点什么话题房间的实际运行截图',
    title: '找个喜欢的话题，随时加入。',
    body: '从课间闲聊到自习搭子，让聊天自然发生。',
    count: '02',
  },
  square: {
    image: './assets/app-square.png',
    alt: '说点什么校园广场的实际运行截图',
    title: '你的日常，也值得被听见。',
    body: '分享校园小事，留下评论，把喜欢的声音收藏起来。',
    count: '03',
  },
};

const tabs = [...document.querySelectorAll('[data-preview]')];
const panel = document.querySelector('#preview-panel');

function selectView(button) {
  if (!button || !panel) return;
  panel.setAttribute('aria-labelledby', button.id);
  const view = views[button.dataset.preview];
  if (!view) return;
  for (const tab of tabs) {
    const active = tab === button;
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
  }
  const image = document.querySelector('#preview-image');
  image.src = view.image;
  image.alt = view.alt;
  document.querySelector('#preview-title').textContent = view.title;
  document.querySelector('#preview-body').textContent = view.body;
  document.querySelector('#preview-count').textContent = view.count;
}

tabs.forEach((button, index) => {
  button.addEventListener('click', () => selectView(button));
  button.addEventListener('keydown', (e) => {
    let target;
    if (e.key === 'ArrowRight') target = tabs[(index + 1) % tabs.length];
    if (e.key === 'ArrowLeft') target = tabs[(index + tabs.length - 1) % tabs.length];
    if (e.key === 'Home') target = tabs[0];
    if (e.key === 'End') target = tabs.at(-1);
    if (target) {
      e.preventDefault();
      selectView(target);
      target.focus();
    }
  });
});

const credits = document.querySelector('#credits-dialog');
const creditsOpen = document.querySelector('#credits-open');
const creditsClose = document.querySelector('#credits-close');
if (credits && creditsOpen && creditsClose) {
  creditsOpen.addEventListener('click', () => credits.showModal());
  creditsClose.addEventListener('click', () => credits.close());
  credits.addEventListener('click', (e) => {
    if (e.target === credits) {
      const r = credits.getBoundingClientRect();
      if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) {
        credits.close();
      }
    }
  });
}

if ('IntersectionObserver' in window && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
  document.body.classList.add('motion-ready');
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.1 }
  );
  document.querySelectorAll('.reveal').forEach((el) => observer.observe(el));
}
