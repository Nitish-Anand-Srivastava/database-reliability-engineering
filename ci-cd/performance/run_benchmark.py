import time, json
results={"query_0":1.1,"query_1":0.9}
with open("current_results.json","w") as f: json.dump(results,f)
