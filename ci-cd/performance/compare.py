import json,sys
b={"query_0":1.0,"query_1":0.8}
c={"query_0":1.1,"query_1":0.9}
for k in b:
 if (c[k]-b[k])/b[k]>0.1:
  sys.exit(1)
print("ok")