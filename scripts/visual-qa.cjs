const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const path=require('node:path');
const origin=process.env.SITE_URL||'http://localhost:8080';
const dir=path.resolve(__dirname,'../artifacts');
async function revealPage(page){
  await page.evaluate(()=>document.fonts.ready);
  const height=await page.evaluate(()=>document.documentElement.scrollHeight);
  for(let y=0;y<height;y+=700){await page.evaluate(y=>scrollTo(0,y),y);await page.waitForTimeout(70);}
  await page.evaluate(()=>Promise.all([...document.images].map(img=>img.decode().catch(()=>{}))));
  await page.evaluate(()=>scrollTo(0,0));await page.waitForTimeout(800);
}
(async()=>{
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1050},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(origin);await revealPage(page);
  assert.equal(await page.locator('.bubble,.paper-stack,.tree-art,.spark').count(),0,'Old generated decorations must be absent');
  assert(await page.locator('.hero-photo').evaluate(e=>e.complete&&e.naturalWidth>=1600),'Referenced hero photograph must load');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  await page.screenshot({path:path.join(dir,'website-desktop.png'),fullPage:true});
  await page.screenshot({path:path.join(dir,'website-desktop-first-screen.png')});
  await page.getByRole('tab',{name:'话题房间'}).click();
  assert.equal(await page.locator('#preview-image').getAttribute('src'),'/assets/app-rooms.png');
  await page.getByRole('tab',{name:'话题房间'}).press('ArrowRight');
  assert.equal(await page.getByRole('tab',{name:'校园广场'}).getAttribute('aria-selected'),'true');
  await page.getByRole('tab',{name:'校园广场'}).press('Home');
  assert.equal(await page.getByRole('tab',{name:'匿名私聊'}).getAttribute('aria-selected'),'true');
  await page.getByText('可以只和同校的人聊天吗？',{exact:true}).click();
  assert(await page.locator('details').nth(1).getAttribute('open')!==null);
  await page.getByRole('button',{name:'素材来源',exact:true}).click();
  assert(await page.locator('#credits-dialog').isVisible());
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('#credits-dialog').isVisible(),false);
  const availability=await(await fetch(origin+'/api/downloads')).json();
  for(const platform of ['android','windows']){
    const link=page.locator('#'+platform+'-download');
    const available=platform==='android'?(availability.androidArm64||availability.android):availability[platform];
    assert.equal(await link.getAttribute('aria-disabled'),String(!available));
    if(available){const href=await link.getAttribute('href');if(platform==='android'&&availability.androidArm64)assert(href.endsWith('-arm64.apk'));const response=await fetch(origin+href,{method:'HEAD'});assert.equal(response.status,200);assert(Number(response.headers.get('content-length'))>1000000);}
  }
  for(const link of await page.locator('[data-download-platform]').all()){
    const key=await link.getAttribute('data-download-platform');
    assert.equal(await link.getAttribute('aria-disabled'),String(!availability[key]));
    if(availability[key]){const href=await link.getAttribute('href');assert.equal((await fetch(origin+href,{method:'HEAD'})).status,200);}
  }
  for(const width of [390,360]){
   await page.setViewportSize({width,height:844});await page.goto(origin);await revealPage(page);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'No overflow at '+width);
   if(width===390){await page.screenshot({path:path.join(dir,'website-mobile.png'),fullPage:true});await page.screenshot({path:path.join(dir,'website-mobile-first-screen.png')});}
   await page.getByRole('button',{name:'展开导航'}).click();assert.equal(await page.locator('#mobile-menu').getAttribute('aria-expanded'),'true');
   await page.locator('#main-nav').getByText('看看 App',{exact:true}).click();assert.equal(await page.locator('#mobile-menu').getAttribute('aria-expanded'),'false');
  }
  assert.deepEqual(errors,[]);
  console.log('PASS: referenced photography loads, 1440/390/360 layouts, gallery keyboard controls, FAQ, source dialog, mobile navigation, real download states.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
