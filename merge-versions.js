(function(root){
  'use strict';
  const YELLOW='FFFFF2CC';
  const clone=value=>value==null?value:structuredClone(value);
  function text(value){
    if(value==null)return '';
    if(typeof value==='object'){
      if(value.richText)return value.richText.map(part=>part.text).join('');
      if('result' in value)return text(value.result);
      if('text' in value)return text(value.text);
    }
    return String(value);
  }
  const key=value=>text(value).replace(/\s+/gu,'').toLowerCase();
  function sourceSheet(sheet){
    let header;
    sheet.eachRow(row=>{
      if(header)return;
      row.eachCell(cell=>{
        if(!header&&key(cell.value)==='englishsource')header={sheet,row:row.number,column:cell.col};
      });
    });
    if(!header)return null;
    header.columns=new Map();
    sheet.getRow(header.row).eachCell(cell=>header.columns.set(key(cell.value),cell.col));
    header.rows=[];
    sheet.eachRow(row=>{
      if(row.number>header.row&&key(row.getCell(header.column).value))header.rows.push(row);
    });
    return header;
  }
  function clearYellow(workbook){
    const yellows=new Set(['FFFF00','FFF2CC','FFFF99','FFFFCC','FFFACD','FFF9C4','FFEB9C']);
    workbook.eachSheet(sheet=>sheet.eachRow(row=>row.eachCell({includeEmpty:true},cell=>{
      const fill=cell.fill,color=fill&&fill.fgColor;
      if(fill&&fill.type==='pattern'&&fill.pattern==='solid'&&color&&
        ((color.argb&&yellows.has(color.argb.slice(-6).toUpperCase()))||color.indexed===6||color.indexed===13)){
        cell.fill={type:'pattern',pattern:'none'};
      }
    })));
  }
  function snapshot(row,width){
    const cells=[];
    for(let col=1;col<=width;col++){
      const cell=row.getCell(col);
      // Materialize shared formulas before their original row is moved.
      const value=cell.type===6?{formula:cell.formula,result:cell.result}:cell.value;
      cells.push({value:clone(value),style:clone(cell.style),note:clone(cell.note)});
    }
    return {cells,height:row.height,hidden:row.hidden,outlineLevel:row.outlineLevel};
  }
  function mergeWorkbooks(original,uploaded){
    const sources=original.worksheets.map(sourceSheet).filter(Boolean);
    const targets=uploaded.worksheets.map(sourceSheet).filter(Boolean);
    if(!sources.length||!targets.length)throw new Error('Both files must contain an English Source column.');
    const used=new Set();
    const pairs=sources.map(source=>{
      let target=targets.find(item=>item.sheet.name===source.sheet.name);
      if(!target&&sources.length===1&&targets.length===1)target=targets[0];
      if(!target||used.has(target))throw new Error('Cannot match worksheet "'+source.sheet.name+'" in the uploaded file.');
      used.add(target);
      return {source,target};
    });
    let changed=false,added=0,removed=0;
    for(const {source,target} of pairs){
      const before=target.rows.map(row=>key(row.getCell(target.column).value));
      const after=source.rows.map(row=>key(row.getCell(source.column).value));
      if(before.length!==after.length||before.some((value,i)=>value!==after[i]))changed=true;
    }
    if(!changed)return {changed:false,added:0,removed:0};
    clearYellow(uploaded);
    for(const {source,target} of pairs){
      const width=target.sheet.columnCount,groups=new Map(),counts=new Map();
      target.rows.forEach(row=>{
        const id=key(row.getCell(target.column).value);
        if(!groups.has(id))groups.set(id,[]);
        groups.get(id).push(snapshot(row,width));
      });
      const template=target.rows.length?snapshot(target.rows[0],width):null;
      const rows=source.rows.map(row=>{
        const id=key(row.getCell(source.column).value),matches=groups.get(id);
        const occurrence=counts.get(id)||0;counts.set(id,occurrence+1);
        let result;
        if(matches){
          result=clone(matches[Math.min(occurrence,matches.length-1)]);
        }else{
          added++;
          result={cells:[],height:template&&template.height};
          for(let col=1;col<=width;col++){
            const name=key(target.sheet.getRow(target.row).getCell(col).value);
            const sourceCol=name&&source.columns.get(name);
            result.cells.push({value:sourceCol?clone(row.getCell(sourceCol).value):null,
              style:template?clone(template.cells[col-1].style):{}});
          }
        }
        result.cells[target.column-1].value=clone(row.getCell(source.column).value);
        if(!matches)result.cells[target.column-1].style.fill={type:'pattern',pattern:'solid',fgColor:{argb:YELLOW}};
        return result;
      });
      groups.forEach((matches,id)=>{removed+=Math.max(0,matches.length-(counts.get(id)||0))});
      const start=target.row+1;
      // Clearing rows explicitly avoids ExcelJS's tail-splice issue and keeps
      // worksheet-level settings and other worksheets in the uploaded workbook.
      target.sheet.eachRow({includeEmpty:true},row=>{
        if(row.number<start)return;
        row.values=[];row.style={};row.height=undefined;row.hidden=false;row.outlineLevel=0;
      });
      rows.forEach((saved,i)=>{
        const row=target.sheet.getRow(start+i);
        row.values=saved.cells.map(cell=>cell.value);
        row.height=saved.height;row.hidden=!!saved.hidden;row.outlineLevel=saved.outlineLevel||0;
        saved.cells.forEach((savedCell,col)=>{
          const cell=row.getCell(col+1);cell.style=savedCell.style;
          cell.note=savedCell.note;
        });
      });
      if(target.sheet.autoFilter){
        const last=Math.max(target.row,target.row+rows.length);
        target.sheet.autoFilter={from:{row:target.row,column:1},to:{row:last,column:width}};
      }
    }
    return {changed:true,added,removed};
  }
  const api={mergeWorkbooks};
  if(typeof module==='object'&&module.exports)module.exports=api;
  else root.MergeVersions=api;
})(typeof globalThis!=='undefined'?globalThis:this);
