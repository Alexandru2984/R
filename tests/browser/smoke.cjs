const { chromium } = require('playwright-core');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const base = process.env.TEST_BASE_URL || 'http://127.0.0.1:43838/';
if (!['127.0.0.1', 'localhost'].includes(new URL(base).hostname)) throw new Error('Browser import tests require a local QA server.');
const artifacts = process.env.TEST_ARTIFACT_DIR || '/tmp/rtraffic-browser-artifacts';
(async () => {
 await fs.mkdir(artifacts, {recursive: true});
 const browser = await chromium.launch({executablePath:process.env.BROWSER_EXECUTABLE || undefined,headless:true});
 try {
 const runPath = '/products?qa=' + Date.now();
 const nginxDay = new Date().toLocaleDateString('en-GB', {timeZone:'UTC',day:'2-digit',month:'short',year:'numeric'}).replaceAll(' ','/');
 const payload = Buffer.from(`${'192.0.2.1'} - - [${nginxDay}:00:01:00 +0000] "GET ${runPath} HTTP/1.1" 200 120 "-" "Mozilla/5.0"\n192.0.2.201 - - [${nginxDay}:00:02:00 +0000] "GET /.env?probe=<svg/onload=window.__trafficXss=1> HTTP/1.1" 404 12 "-" "curl/8.0"\ninvalid line\n`);
 const context = await browser.newContext({viewport:{width:1440,height:1000},acceptDownloads:true});
 const errors=[];
 context.on('page', current => {
   current.on('pageerror', error => errors.push(error.stack));
   current.on('console', msg => { if(msg.type()==='error') errors.push(msg.text()); });
 });
 const page = await context.newPage();
 await page.goto(base, {waitUntil:'networkidle'});
 await page.waitForFunction(()=>document.querySelector('#total_req')?.textContent.trim().match(/[1-9]/),{timeout:30000});
 await page.screenshot({path:path.join(artifacts,'desktop.png'),fullPage:true});
 console.log('initial',await page.locator('#total_req').textContent(),await page.locator('#coverage').innerText());
 assert.equal(await page.locator('a[data-value="Logs & Import"]').isVisible(),false);
 await page.selectOption('#date_preset','today');
 await page.waitForFunction(()=>document.querySelector('#date_start').value===document.querySelector('#date_end').value);
 await page.locator('#reset_filters').click();await page.waitForFunction(()=>document.querySelector('#date_start').value!==document.querySelector('#date_end').value);
 await page.selectOption('#class_filter','scanner');
 await page.waitForFunction(()=>Number(document.querySelector("#total_req").textContent.replaceAll(",",""))<2000);
 console.log('scanner',await page.locator('#total_req').textContent());
 const [download] = await Promise.all([page.waitForEvent('download'),page.locator('#export_csv').click()]);
 const exportFile=await download.path();const csv=await fs.readFile(exportFile,'utf8');
 assert.ok(csv.includes('Synthetic demo'));assert.ok(csv.includes('scanner'));assert.ok(!csv.includes('\"likely_human\"'));
 await page.locator('#reset_filters').click(); await page.waitForFunction(()=>Number(document.querySelector('#total_req').textContent.replaceAll(',',''))>4000);
 await page.locator('#table_top_ips tbody tr').first().click();
 await page.locator('.modal.show').waitFor();
 console.log('investigation',await page.locator('.modal.show').innerText());
 await page.getByRole('button',{name:'Close',exact:true}).click();
 await page.locator('#path_filter').fill('/nothing-matches-this');await page.waitForFunction(()=>document.querySelector('#total_req').textContent.trim()==='0');
 assert.equal((await page.locator('#total_req').textContent()).trim(),'0');
 await page.locator('#reset_filters').click();await page.waitForFunction(()=>Number(document.querySelector('#total_req').textContent.replaceAll(',',''))>4000);
 await page.locator('#btn_login_modal').click();await page.locator('#auth_user').fill('qa');await page.locator('#auth_pass').fill('local-qa-only');await page.locator('#btn_login_submit').click();
 await page.waitForFunction(()=>document.querySelector('#demo_banner')?.textContent.includes('PRIVATE WORKSPACE'));
 await page.locator('a[data-value="Logs & Import"]').click();
 await page.locator('#log_upload').setInputFiles({name:'sample.log',mimeType:'text/plain',buffer:payload});
 await page.waitForFunction(()=>document.querySelector('#upload_status')?.textContent.includes('Preview ready'));
 console.log('preview',await page.locator('#upload_status').textContent());
 assert.equal(await page.evaluate(()=>window.__trafficXss),undefined);
 assert.equal(await page.locator('#import_preview svg').count(),0);
 await page.locator('#btn_process').click();await page.waitForFunction(()=>/Imported|Import failed/.test(document.querySelector('#upload_status')?.textContent)); console.log('import result',await page.locator('#upload_status').textContent()); assert.ok((await page.locator('#upload_status').textContent()).includes('Imported 2'));
 await page.locator('#log_upload').setInputFiles({name:'duplicate.log',mimeType:'text/plain',buffer:payload});
 await page.waitForFunction(()=>document.querySelector('#upload_status')?.textContent.includes('Preview ready'));
 await page.locator('#btn_process').click();await page.waitForFunction(()=>document.querySelector('#upload_status')?.textContent.includes('Import failed'));
 await page.locator('#btn_logout').click();await page.waitForFunction(()=>document.querySelector('#demo_banner')?.textContent.includes('INTERACTIVE DEMO'));
 await page.waitForFunction(()=>Number(document.querySelector("#total_req").textContent.replaceAll(",",""))>1000);
 assert.ok(parseInt((await page.locator('#total_req').textContent()).replaceAll(',',''))>1000);
 for(const width of [360,390,768]){
  const mobile=await context.newPage();await mobile.setViewportSize({width,height:900});await mobile.goto(base); await mobile.waitForFunction(()=>document.querySelector('#total_req')?.textContent.match(/[1-9]/));
  const dimensions=await mobile.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
  console.log('viewport',dimensions);
  assert.ok(dimensions.scroll<=width+1,'horizontal page overflow at '+width);
  if (width < 768) { await mobile.getByRole('button',{name:'Toggle navigation'}).click(); await mobile.locator('#btn_login_modal').waitFor({state:'visible'}); await mobile.getByRole('button',{name:'Toggle navigation'}).click(); }
  await mobile.screenshot({path:path.join(artifacts,`mobile-${width}.png`),fullPage:true}); assert.equal(await mobile.locator('.collapse-toggle').getAttribute('aria-expanded'), width < 768 ? 'false' : 'true'); await mobile.close();
 }
 console.log('browser errors',errors);assert.equal(errors.length,0);
 console.log('PASS desktop, filters, exports, IP investigation, login, import preview, duplicate rejection, logout, mobile layouts');
 } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exit(1)});
