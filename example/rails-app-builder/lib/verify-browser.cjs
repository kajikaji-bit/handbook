const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.HANDBOOK_PLAYWRIGHT_MODULE || '/home/linuxbrew/.linuxbrew/lib/node_modules/@playwright/cli/node_modules/playwright');
const [app, base, evidence] = process.argv.slice(2);
(async () => {
  const design = JSON.parse(fs.readFileSync(path.join(app, 'handbook-design.json')));
  const browser = await chromium.launch({headless:true});
  const page = await browser.newPage();
  const report = {success:false, url:base, resources:[]};
  function assertValues(text, resource, values, location) {
    for (const field of resource.attributes) {
      const expected = field.type === 'datetime' ? values[field.name].replace('T', ' ') : values[field.name];
      assert(text.includes(expected), `${location}の ${field.name}: ${expected}`);
    }
  }
  try {
    for (const resource of design.resources) {
      assert(resource.operations.includes('create'), '画面からテストデータを作る操作が必要です');
      const inflections = JSON.parse(fs.readFileSync(path.join(app, 'handbook-paths.json')));
      const {singular, plural} = inflections[resource.name];
      const url = `${base}/${plural}`;
      const unique = `Handbook-${Date.now()}`;
      const values = {};
      await page.goto(`${url}/new`);
      for (const field of resource.attributes) {
        const element = page.locator(`#${singular}_${field.name}`);
        let value;
        switch(field.type) {
          case 'boolean': await element.check(); value = 'true'; break;
          case 'integer': case 'bigint': value = '42'; await element.fill(value); break;
          case 'decimal': case 'float': value = '12.5'; await element.fill(value); break;
          case 'date': value = '2026-10-04'; await element.fill(value); break;
          case 'datetime': value = '2026-10-04T12:00'; await element.fill(value); break;
          case 'time': value = '12:00'; await element.fill(value); break;
          default: value = `${unique}-${field.name}`; await element.fill(value);
        }
        values[field.name] = value;
      }
      await page.screenshot({path:path.join(evidence, `${resource.name}-form.png`),fullPage:true});
      await Promise.all([page.waitForURL(u => !u.pathname.endsWith('/new')),page.getByRole('button',{name:'保存',exact:true}).click()]);
      const operations = ['create'];
      let recordPath = /^\/[^/]+\/\d+$/.test(new URL(page.url()).pathname) ? new URL(page.url()).pathname : null;
      if (resource.operations.includes('index')) {
        await page.goto(url);
        const articles = page.locator('article');
        let record = null;
        const textField = resource.attributes.find(f => ['string','text'].includes(f.type));
        if (textField) record = articles.filter({hasText:values[textField.name]});
        else record = articles.last();
        assert.equal(await record.count(),1);
        const id = (await record.getAttribute('id')).replace('record_','');
        recordPath = `/${plural}/${id}`;
        const text = await record.innerText();
        assertValues(text, resource, values, '一覧');
        operations.push('index');
        await page.screenshot({path:path.join(evidence,`${resource.name}-index.png`),fullPage:true});
      }
      if (resource.operations.includes('show')) {
        assert(recordPath,'詳細のレコード URL が必要です');
        await page.goto(base+recordPath);
        const text = await page.locator('body').innerText();
        assertValues(text, resource, values, '詳細');
        operations.push('show');
        await page.screenshot({path:path.join(evidence,`${resource.name}-show.png`),fullPage:true});
      }
      if (resource.operations.includes('update')) {
        assert(recordPath); const field=resource.attributes.find(f=>['string','text'].includes(f.type));assert(field,'更新を確認する文字列属性が必要です');
        await page.goto(base+recordPath+'/edit');
        const value=unique+'-updated';await page.locator(`#${singular}_${field.name}`).fill(value);
        await Promise.all([page.waitForURL(u=>!u.pathname.endsWith('/edit')),page.getByRole('button',{name:'保存',exact:true}).click()]);
        await page.goto(resource.operations.includes('show') ? base+recordPath : url);
        assert((await page.locator('body').innerText()).includes(value));operations.push('update');
      }
      if (resource.operations.includes('destroy')) {
        assert(resource.operations.includes('index'),'削除後の一覧確認が必要です');await page.goto(url);
        const id=recordPath.split('/').pop();const record=page.locator(`#record_${id}`);
        await Promise.all([page.waitForResponse(r=>r.request().method()==='POST'),record.getByRole('button',{name:'削除',exact:true}).click()]);
        await page.goto(url);assert.equal(await page.locator(`#record_${id}`).count(),0);operations.push('destroy');
      }
      assert.deepEqual([...operations].sort(),[...resource.operations].sort());
      report.resources.push({name:resource.name,values,operations,url,record_url:recordPath && base+recordPath});
    }
    report.success=true;
    report.url=report.resources[0].url;
    fs.writeFileSync(path.join(evidence,'report.json'),JSON.stringify(report,null,2));
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
