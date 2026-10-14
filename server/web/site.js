'use strict';

// Capability probes, read once. RM gates everything that moves; FINE gates pointer-driven effects.
const RM = matchMedia('(prefers-reduced-motion: reduce)').matches;
const FINE = matchMedia('(hover: hover) and (pointer: fine)').matches;

/* —— Downloads: links stay disabled until /api/downloads confirms a build —— */
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

function setDownload(link, available, url) {
  if (!link) return;
  const target = url || link.dataset.url;
  link.setAttribute('aria-disabled', String(!available));
  if (available && target) link.setAttribute('href', target);
  else link.removeAttribute('href');
}

function setNote(link, text) {
  const note = link ? link.querySelector('small') : null;
  if (note) note.textContent = text;
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
      arm64 ? './downloads/sayanything-android-arm64.apk' : undefined
    );
    setDownload(downloadLinks.windows, data.windows === true);
    setNote(downloadLinks.android, android ? `${arm64 ? 'Android 64 位' : '安卓通用版'} · v1.5.0` : '安装包准备中');
    setNote(downloadLinks.windows, data.windows ? 'Windows x64 · v1.5.0' : '安装包准备中');
    for (const link of variantLinks) {
      setDownload(link, data[link.dataset.downloadPlatform] === true);
    }
    if (status) {
      status.textContent =
        android || data.windows
          ? '自签测试发行版。安装后，连接你的校园服务即可使用。'
          : '安装包准备中，发布后可在这里下载。';
    }
  } catch {
    for (const link of Object.values(downloadLinks)) setNote(link, '暂时无法检查');
    if (status) status.textContent = '暂时无法连接下载服务，请稍后刷新重试。';
  }
}

checkDownloads();

/* —— Header: transparent over the top of the hero, solid once the page moves —— */
const header = document.querySelector('.site-header');
if (header) {
  if ('IntersectionObserver' in window) {
    const sentinel = document.createElement('div');
    sentinel.setAttribute('aria-hidden', 'true');
    sentinel.style.cssText = 'position:absolute;top:0;left:0;width:1px;height:40px;pointer-events:none;';
    document.body.prepend(sentinel);
    new IntersectionObserver((entries) => {
      for (const entry of entries) header.classList.toggle('is-solid', !entry.isIntersecting);
    }).observe(sentinel);
  } else {
    header.classList.add('is-solid');
  }
}

/* —— Mobile navigation —— */
const menu = document.querySelector('#mobile-menu');
const nav = document.querySelector('#main-nav');
if (menu && nav) {
  const closeMenu = () => {
    nav.classList.remove('open');
    menu.setAttribute('aria-expanded', 'false');
  };
  menu.addEventListener('click', () => {
    const open = menu.getAttribute('aria-expanded') !== 'true';
    menu.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('open', open);
  });
  nav.querySelectorAll('a').forEach((a) => a.addEventListener('click', closeMenu));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menu.getAttribute('aria-expanded') === 'true') closeMenu();
  });
}

/* —— App preview: tabs turn the dial and scan the new screen in —— */
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
const previewImage = document.querySelector('#preview-image');
const previewTitle = document.querySelector('#preview-title');
const previewBody = document.querySelector('#preview-body');
const previewCount = document.querySelector('#preview-count');
let currentTab = Math.max(0, tabs.findIndex((tab) => tab.getAttribute('aria-selected') === 'true'));
let dialTurn = 0;

function scanPanel() {
  if (RM || !panel) return;
  panel.classList.remove('is-scanning');
  void panel.offsetWidth; // restart the sweep even when tabs change quickly
  panel.classList.add('is-scanning');
}

function turnDial(index) {
  if (!panel || index < 0 || index === currentTab) return;
  // Always take the short way round: one channel is a third of a turn.
  let step = index - currentTab;
  if (step > tabs.length / 2) step -= tabs.length;
  if (step < -tabs.length / 2) step += tabs.length;
  dialTurn -= step * (360 / tabs.length);
  currentTab = index;
  panel.style.setProperty('--turn', `${dialTurn}deg`);
  panel.dataset.channel = String(index + 1);
  scanPanel();
}

function selectView(button) {
  if (!button || !panel) return;
  const view = views[button.dataset.preview];
  if (!view) return;
  panel.setAttribute('aria-labelledby', button.id);
  for (const tab of tabs) {
    const active = tab === button;
    tab.setAttribute('aria-selected', String(active));
    tab.tabIndex = active ? 0 : -1;
  }
  if (previewImage) {
    previewImage.src = view.image;
    previewImage.alt = view.alt;
    if (!RM && typeof previewImage.animate === 'function') {
      previewImage.animate([{ opacity: 0.18 }, { opacity: 1 }], {
        duration: 760,
        easing: 'cubic-bezier(.16,1,.3,1)',
      });
    }
  }
  if (previewTitle) previewTitle.textContent = view.title;
  if (previewBody) previewBody.textContent = view.body;
  if (previewCount) previewCount.textContent = view.count;
  turnDial(tabs.indexOf(button));
}

tabs.forEach((button, index) => {
  button.addEventListener('click', () => selectView(button));
  button.addEventListener('keydown', (e) => {
    let target;
    if (e.key === 'ArrowRight') target = tabs[(index + 1) % tabs.length];
    if (e.key === 'ArrowLeft') target = tabs[(index + tabs.length - 1) % tabs.length];
    if (e.key === 'Home') target = tabs[0];
    if (e.key === 'End') target = tabs[tabs.length - 1];
    if (target) {
      e.preventDefault();
      selectView(target);
      target.focus();
    }
  });
});

// Warm the other two screenshots once the page has settled, so a tab switch never flashes empty.
window.addEventListener(
  'load',
  () => {
    const warm = () => {
      for (const view of Object.values(views)) {
        const img = new Image();
        img.decoding = 'async';
        img.src = view.image;
      }
    };
    if ('requestIdleCallback' in window) requestIdleCallback(warm, { timeout: 3000 });
    else setTimeout(warm, 1500);
  },
  { once: true }
);

/* —— Credits dialog —— */
const credits = document.querySelector('#credits-dialog');
const creditsOpen = document.querySelector('#credits-open');
const creditsClose = document.querySelector('#credits-close');
if (credits && creditsOpen && creditsClose && typeof credits.showModal === 'function') {
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

/* —— Arrival: rules draw, reticles lock, blocks settle, the wordmark is scanned in.
   Without IntersectionObserver or with reduced motion, nothing is hidden in the first place. —— */
if ('IntersectionObserver' in window && !RM) {
  document.body.classList.add('motion-ready');
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        entry.target.classList.add('is-visible');
        if (entry.target === panel) scanPanel();
        observer.unobserve(entry.target);
      }
    },
    { threshold: 0.12, rootMargin: '0px 0px -4% 0px' }
  );
  document.querySelectorAll('.reveal, .sec, .hud, .scan-reveal').forEach((el) => observer.observe(el));
}

/* —— Download hull: a faint signal light follows a fine pointer (transform only) —— */
const lightHost = document.querySelector('.download-panel');
const light = lightHost ? lightHost.querySelector('.spot') : null;
if (lightHost && light && FINE && !RM) {
  let frame = 0;
  let px = 0;
  let py = 0;
  const paint = () => {
    frame = 0;
    light.style.transform = `translate3d(${px}px, ${py}px, 0)`;
  };
  lightHost.addEventListener(
    'pointermove',
    (e) => {
      const r = lightHost.getBoundingClientRect();
      px = e.clientX - r.left;
      py = e.clientY - r.top;
      if (!frame) frame = requestAnimationFrame(paint);
    },
    { passive: true }
  );
  lightHost.addEventListener('pointerenter', () => lightHost.classList.add('is-lit'));
  lightHost.addEventListener('pointerleave', () => lightHost.classList.remove('is-lit'));
}

/* —— Hero loop video —— */
const heroVideo = document.querySelector('.hero-video');
const heroSection = document.querySelector('.hero');
if (heroVideo && heroSection) {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    // CSS hides the video and the photo shows; make sure it does not play or download further.
    heroVideo.removeAttribute('autoplay');
    heroVideo.pause();
  } else {
    let heroVisible = true;
    // While the generated loop is on screen the photograph is hidden, so its
    // credit is too (it stays in the 素材来源 dialog and returns with the photo).
    heroVideo.addEventListener('playing', () => heroSection.classList.add('is-video'));
    const hideHeroVideo = () => {
      heroVideo.pause();
      heroVideo.style.display = 'none';
      heroSection.classList.remove('is-video');
    };
    const syncHeroVideo = () => {
      if (heroVideo.style.display === 'none') return;
      if (document.hidden || !heroVisible) {
        heroVideo.pause();
        return;
      }
      const playing = heroVideo.play();
      if (playing && typeof playing.catch === 'function') {
        // AbortError just means a pause() interrupted this play(); anything else means autoplay is blocked.
        playing.catch((err) => {
          if (!err || err.name !== 'AbortError') hideHeroVideo();
        });
      }
    };
    heroVideo.addEventListener('error', hideHeroVideo);
    heroVideo.querySelectorAll('source').forEach((source) => source.addEventListener('error', hideHeroVideo));
    document.addEventListener('visibilitychange', syncHeroVideo);
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(
        (entries) => {
          for (const entry of entries) heroVisible = entry.isIntersecting;
          syncHeroVideo();
        },
        { threshold: 0.05 }
      ).observe(heroSection);
    } else {
      syncHeroVideo();
    }
  }
}
