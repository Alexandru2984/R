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
 context.setDefaultTimeout(20000);
 const errors=[];
 context.on('page', current => {
   current.on('pageerror', error => errors.push(error.stack));
   current.on('console', msg => { if(msg.type()==='error') errors.push(msg.text()); });
 });
 async function settleMobileNavigation(current) {
   await current.waitForFunction(()=>!document.querySelector('.navbar-collapse')?.classList.contains('collapsing'));
 }
 async function openMobileNavigation(current) {
   await settleMobileNavigation(current);
   const open = await current.locator('.navbar-collapse').evaluate(el=>el.classList.contains('show') || el.classList.contains('in'));
   if(!open) await current.getByRole('button',{name:'Toggle navigation'}).click();
   await settleMobileNavigation(current);
   await current.locator('a[data-value="Dashboard"]').waitFor({state:'visible'});
 }
 const page = await context.newPage();
 await page.goto(base, {waitUntil:'networkidle'});
 await page.waitForFunction(()=>document.querySelector('#total_req')?.textContent.trim().match(/[1-9]/),{timeout:30000});
 await page.screenshot({path:path.join(artifacts,'desktop.png'),fullPage:true});
 console.log('initial',await page.locator('#total_req').textContent(),await page.locator('#coverage').innerText());
 assert.equal(await page.locator('a[data-value="Logs & Import"]').isVisible(),false);
 await page.locator('#compare_period').check();
 await page.locator('.comparison-table tbody tr').first().waitFor();
 assert.ok((await page.locator('#comparison_summary').innerText()).includes('Previous:'));
 await page.waitForFunction(()=>!!document.querySelector('#chart_activity')?._fullLayout);
 const [reportDownload]=await Promise.all([page.waitForEvent('download'),page.locator('#export_report').click()]);
 assert.ok((await fs.readFile(await reportDownload.path(),'utf8')).includes('PREVIOUS PERIOD'));console.log('comparison and report verified');
 await page.selectOption('#status_filter','4xx');
 await page.locator('#path_filter').fill('/.env');
 await page.locator('#view_name').fill('Sensitive endpoint errors');
 await page.locator('#save_view').click();
 await page.waitForFunction(()=>document.querySelector('#saved_view').value.startsWith('view'));
 await page.locator('#reset_filters').click();
 await page.waitForFunction(()=>document.querySelector('#path_filter').value==='');
 await page.locator('#load_view').click();
 await page.waitForFunction(()=>document.querySelector('#path_filter').value==='/.env' && document.querySelector('#status_filter').value==='4xx');
 await page.locator('#delete_view').click();await page.waitForFunction(()=>document.querySelector('#saved_view').options.length===1);console.log('saved views verified');
 await page.locator('#reset_filters').click();
 await page.waitForFunction(()=>Number(document.querySelector('#total_req').textContent.replaceAll(',',''))>4000);
 await page.locator('a[data-value="Detection lab"]').click();
 await page.waitForFunction(()=>document.querySelector('#lab_result')?.textContent.includes('13'));
 assert.ok((await page.locator('#lab_result').innerText()).includes('Scanner signals'));
 await page.selectOption('#lab_example','login');
 await page.waitForFunction(()=>document.querySelector('#lab_result')?.textContent.includes('Likely human'));
 await page.locator('#lab_path').fill('/<svg/onload=window.__labXss=1>');
 await page.waitForTimeout(500);
 assert.equal(await page.evaluate(()=>window.__labXss),undefined);
 console.log('detection lab verified');await page.locator('a[data-value="Dashboard"]').click();
 await page.selectOption('#date_preset','today');
 await page.waitForFunction(()=>document.querySelector('#date_start').value===document.querySelector('#date_end').value);
 await page.locator('#reset_filters').click();await page.waitForFunction(()=>document.querySelector('#date_start').value!==document.querySelector('#date_end').value);
 await page.selectOption('#class_filter','scanner');
 await page.waitForFunction(()=>{ const n=Number(document.querySelector('#total_req').textContent.replaceAll(',','')); const flagged=Number(document.querySelector('#sus_bots').textContent.replaceAll(',','')); return n>0 && n<2000 && n===flagged; });
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
 await page.locator('#view_name').fill('Demo view before login');await page.locator('#save_view').click();await page.waitForFunction(()=>document.querySelector('#saved_view').options.length===2);
 await page.locator('#btn_login_modal').click();await page.locator('#auth_user').fill('qa');await page.locator('#auth_pass').fill('local-qa-only');await page.locator('#btn_login_submit').click();
 await page.waitForFunction(()=>document.querySelector('#demo_banner')?.textContent.includes('PRIVATE WORKSPACE'));
 await page.waitForFunction(()=>document.querySelector('#saved_view').options.length===1);
 await page.locator('a[data-value="Logs & Import"]').click();
 await page.locator('#log_upload').setInputFiles({name:'sample.log',mimeType:'text/plain',buffer:payload});
 await page.waitForFunction(()=>document.querySelector('#upload_status')?.textContent.includes('Preview ready'));
 console.log('preview',await page.locator('#upload_status').textContent());
 assert.equal(await page.evaluate(()=>window.__trafficXss),undefined);
 assert.equal(await page.locator('#import_preview svg').count(),0);
 await page.locator('#btn_process').click();await page.waitForFunction(()=>/Imported|Import failed/.test(document.querySelector('#upload_status')?.textContent)); console.log('import result',await page.locator('#upload_status').textContent()); assert.ok((await page.locator('#upload_status').textContent()).includes('Imported 2'));
 await page.waitForFunction(()=>document.querySelector('#audit_history')?.textContent.includes('import_completed'));
 await page.locator('#log_upload').setInputFiles({name:'duplicate.log',mimeType:'text/plain',buffer:payload});
 await page.waitForFunction(()=>document.querySelector('#upload_status')?.textContent.includes('Preview ready'));
 await page.locator('#btn_process').click();await page.waitForFunction(()=>document.querySelector('#upload_status')?.textContent.includes('Import failed'));
 await page.locator('#btn_logout').click();await page.waitForFunction(()=>document.querySelector('#demo_banner')?.textContent.includes('INTERACTIVE DEMO'));
 await page.waitForFunction(()=>Number(document.querySelector("#total_req").textContent.replaceAll(",",""))>1000);
 await page.waitForFunction(()=>!document.querySelector('#audit_history')?.textContent.includes('import_completed'));
 await page.waitForFunction(()=>document.querySelector('#path_filter').value==='' && !document.querySelector('#log_upload'));
 assert.ok(parseInt((await page.locator('#total_req').textContent()).replaceAll(',',''))>1000);
 for(const width of [360,390,768]){
  const mobile=await context.newPage();await mobile.setViewportSize({width,height:900});await mobile.goto(base); await mobile.waitForFunction(()=>document.querySelector('#total_req')?.textContent.match(/[1-9]/));
  if(width<768){ await mobile.locator('.collapse-toggle').click();await mobile.locator('#view_name').scrollIntoViewIfNeeded();await mobile.locator('#view_name').fill('Mobile view');await mobile.locator('#save_view').click();await mobile.waitForFunction(()=>document.querySelector('#saved_view').options.length===2);await mobile.locator('.collapse-toggle').click(); }
  const dimensions=await mobile.evaluate(()=>({width:innerWidth,scroll:document.documentElement.scrollWidth}));
  console.log('viewport',dimensions);
  assert.ok(dimensions.scroll<=width+1,'horizontal page overflow at '+width);
  if (width < 768) { await openMobileNavigation(mobile); await mobile.locator('#btn_login_modal').waitFor({state:'visible'}); await mobile.getByRole('button',{name:'Toggle navigation'}).click(); await settleMobileNavigation(mobile); }
  if(width<768){
    await openMobileNavigation(mobile);
    await mobile.locator('a[data-value="Detection lab"]').click();
    await mobile.waitForFunction(()=>document.querySelector('#lab_result')?.textContent.includes('13'));
    assert.ok(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
    await mobile.screenshot({path:path.join(artifacts,`lab-mobile-${width}.png`),fullPage:true});
    await openMobileNavigation(mobile);
    await mobile.locator('a[data-value="Dashboard"]').click();
    await settleMobileNavigation(mobile);
    const stillOpen=await mobile.locator('.navbar-collapse').evaluate(el=>el.classList.contains('show') || el.classList.contains('in'));
    if(stillOpen) { await mobile.getByRole('button',{name:'Toggle navigation'}).click(); await settleMobileNavigation(mobile); }
  }
  await mobile.screenshot({path:path.join(artifacts,`mobile-${width}.png`),fullPage:true}); assert.equal(await mobile.locator('.collapse-toggle').getAttribute('aria-expanded'), width < 768 ? 'false' : 'true'); await mobile.close();
 }
 console.log('browser errors',errors);assert.equal(errors.length,0);
 console.log('PASS desktop/mobile, comparison, heatmap, saved views, detection lab, private audit, imports, exports and logout');
 } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exit(1)});
