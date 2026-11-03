const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const ExcelJS=require(process.env.EXCELJS_TEST_PATH||'exceljs');
const MergeVersions=require('../merge-versions.js');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const controller=html.slice(html.indexOf('// Merge locally:'),html.indexOf('// Owners may delete their entries;'));
async function excel(rows){
  const book=new ExcelJS.Workbook();book.addWorksheet('Language').addRows(rows);
  return book.xlsx.writeBuffer();
}
function harness(original){
  const elements=new Map(),downloads=[],queries=[];
  const element=id=>{
    if(!elements.has(id))elements.set(id,{hidden:true,textContent:'',value:'',classList:{remove(){},add(){}},
      setAttribute(name,value){this[name]=value},focus(){},click(){},remove(){}});
    return elements.get(id);
  };
  const query={};
  for(const name of ['select','eq','order','limit'])query[name]=(...args)=>{queries.push([name,...args]);return query};
  query.maybeSingle=async()=>({data:{id:'newest',storage_path:'latest.xlsx'}});
  const context={ExcelJS,MergeVersions,Blob,Promise,console,
    $:element,uid:'user',curFolder:{id:'english-id',name:'English'},files:[{id:'existing'}],MAXB:5*1024*1024,
    TBL:'balcony_language',XLSX_MIME:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    sb:{from:()=>query},pubUrl:path=>'https://test.invalid/'+path,
    fetch:async()=>({ok:true,arrayBuffer:async()=>original}),folderKey:name=>name.toLowerCase(),
    openModal:id=>{element(id).hidden=false},needLogin:()=>{context.loginRequested=true},
    setTimeout:()=>{},URL:{createObjectURL(blob){downloads.push(blob);return 'blob:test'},revokeObjectURL(){}},
    document:{createElement(){return {click(){},remove(){}}},body:{appendChild(){}}}
  };
  context.window=context;
  context.closeModal=id=>{element(id).hidden=true;context.resetMerge()};
  vm.createContext(context);vm.runInContext(controller,context);
  return {context,element,downloads,queries};
}
test('selection merges the newest original, download closes and clears the dialog',async()=>{
  const a=await excel([['English Source'],['Apple'],['Banana']]);
  const b=await excel([['English Source','Chinese'],['Banana','香蕉'],['Cherry','櫻桃']]);
  const {context,element,downloads,queries}=harness(a);
  element('fmerge').onclick();
  assert.equal(element('mmodal').hidden,false);
  await context.mergeSelectedFile({name:'translation.xlsx',size:b.length,arrayBuffer:async()=>b});
  assert.equal(element('merr').textContent,'');
  assert.equal(element('mdownload').hidden,false);
  assert.ok(queries.some(([name,column,options])=>name==='order'&&column==='created_at'&&options.ascending===false));
  assert.ok(queries.some(([name,column,value])=>name==='eq'&&column==='folder_id'&&value==='english-id'));
  element('mdownload').onclick();
  assert.equal(downloads.length,1);
  const output=new ExcelJS.Workbook();await output.xlsx.load(await downloads[0].arrayBuffer());
  assert.equal(output.worksheets[0].getCell('A2').value,'Apple');
  assert.equal(output.worksheets[0].getCell('B3').value,'香蕉');
  assert.equal(element('mmodal').hidden,true);
  assert.equal(context.mergeResult,null);
});
test('identical input hides download and shows the agreed English message',async()=>{
  const a=await excel([['English Source'],['Banana']]);
  const b=await excel([['English Source','Chinese'],['banana','香蕉']]);
  const {context,element}=harness(a);element('fmerge').onclick();
  await context.mergeSelectedFile({name:'translation.xlsx',size:b.length,arrayBuffer:async()=>b});
  assert.equal(element('mdownload').hidden,true);
  assert.equal(element('mstatus').textContent,'The files are identical. No rows need to be merged.');
});
test('invalid files show errors and closing cancels an in-flight merge',async()=>{
  const a=await excel([['English Source'],['Apple']]);
  const {context,element}=harness(a);element('fmerge').onclick();
  await context.mergeSelectedFile({name:'bad.csv',size:10});
  assert.equal(element('merr').textContent,'Only .xlsx files.');
  await context.mergeSelectedFile({name:'large.xlsx',size:6*1024*1024});
  assert.equal(element('merr').textContent,'Max 5 MB.');
  let finish;
  const pending=new Promise(resolve=>{finish=resolve});
  const merging=context.mergeSelectedFile({name:'translation.xlsx',size:10,arrayBuffer:()=>pending});
  context.closeModal('mmodal');finish(a);await merging;
  assert.equal(context.mergeResult,null);
  assert.equal(element('mdownload').hidden,true);
  assert.equal(element('mstatus').textContent,'');
});
test('login and existing original are required before selecting a file',async()=>{
  const {context,element}=harness(null);context.uid=null;element('fmerge').onclick();
  assert.equal(context.loginRequested,true);
  assert.equal(context.mergeFolderId,null);
  context.uid='user';context.files=[];element('fmerge').onclick();
  assert.equal(context.mergeFolderId,null);
});
