// Render the referenced Lucide SVG to the raster formats required by launchers.
const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
(async()=>{
 const root=path.resolve(__dirname,'..');
 const svg=fs.readFileSync(path.join(root,'client/web/favicon.svg'),'utf8');
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try{
  const page=await browser.newPage();
  await page.setContent('<html><style>html,body{margin:0;background:transparent}svg{width:100vw;height:100vh;display:block}</style>'+svg+'</html>');
  for(const size of [192,512]){
    await page.setViewportSize({width:size,height:size});
    await page.screenshot({path:path.join(root,`client/web/icons/Icon-${size}.png`),omitBackground:true});
    fs.copyFileSync(path.join(root,`client/web/icons/Icon-${size}.png`),path.join(root,`client/web/icons/Icon-maskable-${size}.png`));
  }
  console.log('Referenced grayscale Lucide launcher icons rendered.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
