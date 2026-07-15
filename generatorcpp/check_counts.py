import os, re
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'generator.cpp')).read()
def body_after(end):
    i=end; depth=1; out=[]
    while i<len(src) and depth>0:
        c=src[i]
        if c=='{':depth+=1
        elif c=='}':
            depth-=1
            if depth==0: break
        out.append(c); i+=1
    return ''.join(out)
lv={}
for m in re.finditer(r'level_fn\s+(LV_\w+)\s*\[\]\s*=\s*\{',src):
    b=body_after(m.end()); lv[m.group(1)]=len([x for x in b.split(',') if x.strip()])
problems=[]; fac={}
for m in re.finditer(r'Factor\s+(F_\w+)\s*\[\]\s*=\s*\{',src):
    b=body_after(m.end())
    entries=re.findall(r'\{\s*"[^"]*"\s*,\s*(LV_\w+)\s*,\s*(\d+)\s*,\s*(?:true|false)\s*\}',b)
    fac[m.group(1)]=len(entries)
    for l,n in entries:
        a=lv.get(l)
        if a is None: problems.append(f"{m.group(1)}: unknown {l}")
        elif a!=int(n): problems.append(f"{m.group(1)}: {l} nlev={n} but array={a}")
for m in re.finditer(r'StmtClass\s+(C_\w+)\s*[={]\s*\{?\s*"[^"]*"\s*,\s*"[^"]*"\s*,\s*(F_\w+)\s*,\s*(\d+)\s*,\s*\d+\s*\}',src):
    a=fac.get(m.group(2))
    if a is None: problems.append(f"{m.group(1)}: unknown {m.group(2)}")
    elif a!=int(m.group(3)): problems.append(f"{m.group(1)}: nfac={m.group(3)} but {m.group(2)}={a}")
print("MISMATCHES:\n"+"\n".join("  "+p for p in problems) if problems else "All nlev/nfac counts match.")
print(f"(checked {len(lv)} LV arrays, {len(fac)} Factor arrays)")
