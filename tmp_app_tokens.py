import os, mimetypes
import tiktoken
root = "/workspace/gitlab/app"
skip_ext = {".png",".jpg",".jpeg",".gif",".svg",".ico",".woff",".woff2",".ttf",".eot",".pdf",".zip",".gz",".bz2",".xz",".7z",".so",".dll",".dylib",".bin",".jar",".war",".mp4",".mp3",".webm",".mov",".psd"}
enc = tiktoken.get_encoding("cl100k_base")
total = 0
lines = 0
files = 0
for dp, _, fns in os.walk(root):
    for fn in fns:
        p = os.path.join(dp, fn)
        ext = os.path.splitext(fn)[1].lower()
        if ext in skip_ext:
            continue
        try:
            with open(p, "r", encoding="utf-8", errors="ignore") as f:
                s = f.read()
                files += 1
                lines += s.count("\n")
                total += len(enc.encode(s))
        except Exception:
            pass
print(f"files={files} lines={lines} tokens={total}")
