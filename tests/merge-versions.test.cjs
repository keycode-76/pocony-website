// Run with ExcelJS 4.4.0 installed, or set EXCELJS_TEST_PATH to its browser bundle.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const ExcelJS=require(process.env.EXCELJS_TEST_PATH||'exceljs');
const {mergeWorkbooks}=require('../merge-versions.js');
function workbook(values,name='Language'){
  const book=new ExcelJS.Workbook(),sheet=book.addWorksheet(name);
  sheet.addRows(values);
  return book;
}
const original=rows=>workbook([['English Source'],...rows.map(value=>[value])]);
const translation=rows=>workbook([['English Source','Chinese'],...rows]);
const values=book=>book.worksheets[0].getSheetValues().slice(2).map(row=>row.slice(1));
const fill=color=>({type:'pattern',pattern:'solid',fgColor:{argb:color}});
async function roundTrip(book){
  const loaded=new ExcelJS.Workbook();
  await loaded.xlsx.load(await book.xlsx.writeBuffer());
  return loaded;
}
test('A controls rows/order, B supplies translation; only added English is yellow',async()=>{
  const a=original(['Apple','Banana']),b=translation([['Banana','香蕉'],['Cherry','櫻桃']]);
  b.worksheets[0].getCell('B2').font={bold:true};
  b.worksheets[0].getColumn(2).width=35;
  const result=mergeWorkbooks(a,b);
  assert.deepEqual(result,{changed:true,added:1,removed:1});
  const output=await roundTrip(b);
  assert.deepEqual(values(output),[['Apple'],['Banana','香蕉']]);
  const sheet=output.worksheets[0];
  assert.equal(sheet.getCell('A2').fill.fgColor.argb,'FFFFF2CC');
  assert.notEqual(sheet.getCell('B2').fill?.fgColor?.argb,'FFFFF2CC');
  assert.equal(sheet.getCell('B3').font.bold,true);
  assert.equal(sheet.getColumn(2).width,35);
});
test('identical normalized sources give no download, without changing B',()=>{
  const a=original([' Hello\nWORLD ','Banana']),b=translation([['hello world','你好'],['BANANA','香蕉']]);
  b.worksheets[0].getCell('A2').fill=fill('FFFFF2CC');
  assert.equal(mergeWorkbooks(a,b).changed,false);
  assert.equal(b.worksheets[0].getCell('A2').value,'hello world');
  assert.equal(b.worksheets[0].getCell('A2').fill.fgColor.argb,'FFFFF2CC');
});
test('deletion only still produces downloadable result',async()=>{
  const b=translation([['Banana','香蕉'],['Cherry','櫻桃']]);
  assert.deepEqual(mergeWorkbooks(original(['Banana']),b),{changed:true,added:0,removed:1});
  assert.deepEqual(values(await roundTrip(b)),[['Banana','香蕉']]);
});
test('reordering only preserves A spelling and B translations',async()=>{
  const b=translation([['banana','香蕉'],['apple','蘋果']]);
  assert.equal(mergeWorkbooks(original(['Apple','Banana']),b).changed,true);
  assert.deepEqual(values(await roundTrip(b)),[['Apple','蘋果'],['Banana','香蕉']]);
});
test('duplicates match translations by occurrence',async()=>{
  const b=translation([['Banana','一'],['Cherry','櫻桃'],['Banana','二']]);
  mergeWorkbooks(original(['Banana','Banana']),b);
  assert.deepEqual(values(await roundTrip(b)),[['Banana','一'],['Banana','二']]);
});
test('one translation is reused for all duplicate source rows',async()=>{
  const b=translation([['Banana','香蕉']]);
  assert.deepEqual(mergeWorkbooks(original(['Banana','Banana']),b),{changed:true,added:0,removed:0});
  assert.deepEqual(values(await roundTrip(b)),[['Banana','香蕉'],['Banana','香蕉']]);
});
test('clear previous yellow, preserve other fills and other worksheet contents',async()=>{
  const b=translation([['Banana','香蕉'],['Cherry','櫻桃']]);
  const sheet=b.worksheets[0];
  sheet.getCell('A2').fill=fill('FFFFF2CC');
  sheet.getCell('B2').fill=fill('FF00FF00');
  const notes=b.addWorksheet('Notes');
  notes.getCell('A1').value='Keep this sheet';notes.getCell('A1').font={italic:true};
  notes.getCell('B1').value=new Date('2026-01-01T00:00:00Z');
  mergeWorkbooks(original(['Apple','Banana']),b);
  const output=await roundTrip(b),merged=output.worksheets[0];
  assert.ok(!merged.getCell('A3').fill||merged.getCell('A3').fill.pattern==='none');
  assert.equal(merged.getCell('B3').fill.fgColor.argb,'FF00FF00');
  assert.equal(output.getWorksheet('Notes').getCell('A1').value,'Keep this sheet');
  assert.equal(output.getWorksheet('Notes').getCell('A1').font.italic,true);
  assert.equal(output.getWorksheet('Notes').getCell('B1').value.toISOString(),'2026-01-01T00:00:00.000Z');
});
test('headers can be below a title and columns can be reordered',async()=>{
  const a=workbook([['Title'],['ID','English Source'],[2,'Apple'],[3,'Banana']]);
  const b=workbook([['Translator notes'],['Chinese','English Source','ID'],['香蕉','Banana',3]]);
  mergeWorkbooks(a,b);
  const output=(await roundTrip(b)).worksheets[0];
  assert.equal(output.getCell('A1').value,'Translator notes');
  assert.equal(output.getCell('B3').value,'Apple');
  assert.equal(output.getCell('C3').value,2);
  assert.equal(output.getCell('A4').value,'香蕉');
});
test('multiple source worksheets match by name',async()=>{
  const a=original(['Apple']);a.addWorksheet('Second').addRows([['English Source'],['Orange']]);
  const b=translation([['Banana','香蕉']]);b.addWorksheet('Second').addRows([['English Source','Chinese'],['Orange','橘子']]);
  assert.equal(mergeWorkbooks(a,b).added,1);
  const output=await roundTrip(b);
  assert.equal(output.getWorksheet('Second').getCell('B2').value,'橘子');
});
test('invalid or ambiguous sheets report a useful error',()=>{
  assert.throws(()=>mergeWorkbooks(original(['Apple']),workbook([['Wrong header']])),/English Source/);
  const a=original(['Apple']);a.addWorksheet('Second').addRows([['English Source'],['Orange']]);
  assert.throws(()=>mergeWorkbooks(a,translation([['Banana','香蕉']])),/Cannot match worksheet/);
});
test('an empty latest data sheet removes all obsolete rows',async()=>{
  const b=translation([['Banana','香蕉']]);
  assert.deepEqual(mergeWorkbooks(original([]),b),{changed:true,added:0,removed:1});
  assert.equal((await roundTrip(b)).worksheets[0].rowCount,1);
});
