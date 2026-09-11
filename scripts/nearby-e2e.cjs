const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const origin=process.env.QA_API_URL||'http://localhost:8081';
const app=process.env.QA_APP_URL||'http://localhost:8090';
const out=path.resolve(__dirname,'../artifacts');
const video=process.env.QA_VIDEO_PATH||path.join(out,'media-fixtures/bee.mp4');
const campus=`附近联测${Date.now()}`;
fs.mkdirSync(out,{recursive:true});
assert(fs.existsSync(video),'Download bee.mp4 fixture first; see docs/assets.md');

async function api(method,route,token,data){
  const r=await fetch(origin+'/api/v1'+route,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:data===undefined?undefined:JSON.stringify(data)});
  const value=r.status===204?null:await r.json();
  assert(r.ok,`${method} ${route}: ${r.status} ${JSON.stringify(value)}`);
  return value;
}
async function poll(fn,message){
  const until=Date.now()+25000;
  while(Date.now()<until){const value=await fn();if(value)return value;await new Promise(r=>setTimeout(r,200));}
  assert.fail(message);
}
async function fill(locator,value){await locator.click();await locator.press('Control+A');await locator.pressSequentially(value,{delay:10});await locator.press('Tab');}
async function tap(page,name){await page.getByRole('button',{name,exact:typeof name==='string'}).first().evaluate(node=>node.click());await page.waitForTimeout(300);}
async function shot(page,name){await page.mouse.move(0,0);await page.waitForTimeout(400);await page.screenshot({path:path.join(out,`nearby-${name}.png`)});}

(async()=>{
  const browser=await chromium.launch({channel:'chrome',headless:true});
  // Synthetic QA position: never read the connected phone's location.
  const context=await browser.newContext({viewport:{width:390,height:844},geolocation:{latitude:31.2,longitude:121.5},permissions:['geolocation']});
  const page=await context.newPage();page.setDefaultTimeout(25000);
  const errors=[],posterResponses=[];
  let puts=0,owner,peer;
  page.on('pageerror',e=>errors.push(e.message));
  page.on('request',r=>{if(r.method()==='PUT'&&r.url().endsWith('/nearby/location'))puts++;});
  page.on('response',r=>{if(r.url().includes('view=poster'))posterResponses.push(r);});
  await page.route('https://d8j0ntlcm91z4.cloudfront.net/**',route=>route.abort('failed'));
  try{
    await page.goto(app,{waitUntil:'domcontentloaded'});await page.locator('flutter-view').waitFor();
    const semantics=page.locator('flt-semantics-placeholder');if(await semantics.count())await semantics.first().evaluate(n=>n.click());
    await fill(page.getByRole('textbox',{name:'你在哪所学校？'}),campus);
    await page.getByRole('checkbox').click();
    const session=page.waitForResponse(r=>r.url().endsWith('/api/v1/session')&&r.request().method()==='POST');
    await tap(page,'进入校园');owner=await(await session).json();
    await page.getByText('校园里的声音',{exact:true}).waitFor();
    await tap(page,'设置');await tap(page,/^性别/);await tap(page,'女');
    await poll(async()=> (await api('GET','/me',owner.token)).gender==='female','gender did not persist');
    await shot(page,'gender');

    peer=await api('POST','/session',null,{campus});
    await api('PATCH','/me',peer.token,{alias:'附近联测同学',gender:'male'});
    let status=await api('GET','/nearby',peer.token);
    await api('PUT','/nearby/location',peer.token,{latitude:31.202,longitude:121.501,revision:status.revision});

    await tap(page,'聊天');await tap(page,'附近的人');
    await page.getByText('开启附近并展示我',{exact:true}).waitFor();
    assert.equal(puts,0,'nearby published before consent');
    assert.equal((await api('GET','/nearby',owner.token)).enabled,false);
    await shot(page,'opt-in');
    await tap(page,'开启附近并展示我');
    await page.getByRole('group',{name:/附近联测同学/}).waitFor();
    assert.equal(puts,1);
    status=await api('GET','/nearby',owner.token);
    assert.equal(status.items[0].gender,'male');
    assert.deepEqual(Object.keys(status.items[0]).sort(),['distanceLabel','gender','id','alias'].sort());
    await shot(page,'people');
    await tap(page,'打招呼');
    await page.getByRole('textbox',{name:'输入消息…'}).waitFor();
    const conversation=await poll(async()=> (await api('GET','/conversations',peer.token))[0],'greeting conversation missing');
    await api('POST',`/nearby/${peer.user.id}/greet`,owner.token,{});
    let messages=await api('GET',`/conversations/${conversation.id}/messages`,peer.token);
    assert.equal(messages.filter(m=>m.body==='你好，方便聊聊吗？').length,1,'repeated greeting duplicated');

    const chooser=page.waitForEvent('filechooser');await tap(page,'添加图片或视频');await(await chooser).setFiles(video);
    await page.getByRole('button',{name:'移除附件 1'}).waitFor();
    const preview=page.locator('video[src^="blob:"]').first();
    await preview.waitFor();
    await poll(()=>preview.evaluate(v=>v.readyState>=2&&v.paused&&(v.muted||v.volume===0)),'draft frame not ready or not muted/paused');
    const frame=await preview.evaluate(v=>{const c=document.createElement('canvas');c.width=32;c.height=32;const x=c.getContext('2d');x.drawImage(v,0,0,32,32);return [...x.getImageData(0,0,32,32).data].some((n,i)=>i%4!==3&&n>30);});
    assert(frame,'draft displayed no real pixels');await shot(page,'draft-cover');
    await tap(page,'发送消息');
    const message=await poll(async()=> (await api('GET',`/conversations/${conversation.id}/messages`,peer.token)).find(m=>m.attachments?.[0]?.kind==='video'),'video message missing');
    const ticket=await api('POST',`/media/${message.attachments[0].id}/ticket`,peer.token,{});
    assert(ticket.posterUrl&&!ticket.posterUrl.includes(peer.token));
    const cover=await fetch(new URL(ticket.posterUrl,origin));assert.equal(cover.status,200);assert(cover.headers.get('content-type').startsWith('image/jpeg'));
    fs.writeFileSync(path.join(out,'video-poster.jpg'),Buffer.from(await cover.arrayBuffer()));
    await poll(()=>posterResponses.some(r=>r.status()===200),'chat did not load server poster');
    await shot(page,'chat-cover');
    await tap(page,/返回|Back/);
    await page.getByText('关闭附近展示',{exact:true}).waitFor();
    const oldRevision=(await api('GET','/nearby',owner.token)).revision;
    await tap(page,'关闭附近展示');
    await poll(async()=> !(await api('GET','/nearby',owner.token)).enabled,'sharing not disabled');
    const stale=await fetch(origin+'/api/v1/nearby/location',{method:'PUT',headers:{Authorization:'Bearer '+owner.token,'Content-Type':'application/json'},body:JSON.stringify({latitude:31.2,longitude:121.5,revision:oldRevision})});
    assert.equal(stale.status,409,'late old location restored sharing');
    assert(!(await api('GET','/nearby',peer.token)).items.some(p=>p.id===owner.user.id));
    assert.deepEqual(errors,[]);
    console.log('PASS nearby + covers: opt-in, gender, coarse discovery, single greeting, real local frame, protected server poster, stale-location rejection.');
  }catch(e){await shot(page,'failure');fs.writeFileSync(path.join(out,'nearby-failure.txt'),await page.locator('body').ariaSnapshot());throw e;}
  finally{await browser.close();for(const user of [owner,peer])if(user?.token)await api('DELETE','/me',user.token).catch(()=>{});}
})().catch(e=>{console.error(e);process.exitCode=1;});
