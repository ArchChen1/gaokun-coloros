import json, subprocess, sys
req = json.load(sys.stdin)
r = subprocess.run(req["argv"], capture_output=True, text=True, cwd=req.get("cwd"))
print(json.dumps({"returncode": r.returncode, "stdout": r.stdout, "stderr": r.stderr}))