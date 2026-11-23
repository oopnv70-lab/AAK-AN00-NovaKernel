#!/bin/bash
# 拉取荣耀开源发布中心的指定机型开源源码并解压（CI / 本地通用）
# 解决下载链接"会过期 + 防盗链"的问题：每次实时查接口拿当前有效签名 URL，再带 Referer 下载。
#
# 用法: fetch_honor_source.sh [MODEL_CODE] [DEST_DIR]
#   默认 MODEL_CODE=AAK-AN00 (荣耀 WIN RT), DEST_DIR=$PWD/honor_src
# 产物: $DEST_DIR/Code_Opensource/{README_*.txt,kernel,external,vendor}
set -euo pipefail

MODEL="${1:-AAK-AN00}"
DEST="${2:-$PWD/honor_src}"
API='https://selfservice-cn.hihonor.com/ccpcmd/services/dispatch/secured/CCPC/EN/tkb/findDocKnow/1000'
REFERER='https://www.honor.com/global/opensource/'
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'

mkdir -p "$DEST"
WORK=$(mktemp -d)

echo "[*] 查询 $MODEL 的当前有效下载地址 ..."
URL=""
FN=""
TOTAL="?"
for p in $(seq 1 10); do
  curl -sG -A "$UA" --max-time 60 "$API" \
    --data-urlencode 'jsonp=cb' --data-urlencode 'siteCode=worldwide' \
    --data-urlencode 'regionCode=GB' --data-urlencode "curPage=$p" \
    --data-urlencode 'pageSize=50' --data-urlencode 'offeringCode=CMCG10000045' \
    --data-urlencode 'channelCode=10005' --data-urlencode 'countryCode=0' \
    --data-urlencode 'country=0' --data-urlencode 'langCode=en-gb' \
    --data-urlencode 'language=en-us' --data-urlencode 'knowledgeTypes=F34' \
    -o "$WORK/p.txt"
  parsed=$(python3 - "$WORK/p.txt" "$MODEL" <<'PY'
import json,re,sys
t=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
code=sys.argv[2]
m=re.search(r'cb\((\{.*\})\)', t, re.S)
if not m:
    print('TOTAL=0'); sys.exit()
o=json.loads(m.group(1)); rd=o.get('responseData',{})
print('TOTAL='+str(rd.get('totalCount','?')))
for it in rd.get('rList',[]):
    if code in it.get('fileName',''):
        print('URL='+it['fileUrl']); print('FN='+it['fileName'])
        print('SIZE='+str(it.get('fileLen','?'))); print('DATE='+str(it.get('releaseDate','?')))
        break
PY
)
  TOTAL=$(echo "$parsed" | sed -n 's/^TOTAL=//p')
  URL=$(echo "$parsed" | sed -n 's/^URL=//p')
  if [ -n "$URL" ]; then
     FN=$(echo "$parsed" | sed -n 's/^FN=//p')
     SZ=$(echo "$parsed" | sed -n 's/^SIZE=//p')
     DT=$(echo "$parsed" | sed -n 's/^DATE=//p')
     echo "[+] 命中第 $p 页: $FN  ${SZ}KB  发布 $DT"
     break
  fi
  np=$(python3 -c "import math;print(math.ceil(int('$TOTAL')/50))" 2>/dev/null || echo 99)
  [ "$p" -ge "${np:-99}" ] && break
done

[ -z "$URL" ] && { echo "[x] 未找到 $MODEL"; exit 2; }

# 取会话 cookie（下载接口防盗链校验）
curl -s -A "$UA" -e "$REFERER" --max-time 30 "$REFERER" -c "$WORK/ck.txt" -o /dev/null || true

ZIP="$DEST/${FN:-$MODEL.zip}"
echo "[*] 下载源码包（带 Referer）-> $ZIP"
curl -L -A "$UA" -e "$REFERER" -b "$WORK/ck.txt" --max-time 3600 \
     --retry 3 --retry-delay 5 "$URL" -o "$ZIP" \
     -w '[+] HTTP=%{http_code} size=%{size_download}B time=%{time_total}s\n'

echo "[*] 解压 ..."
unzip -q -o "$ZIP" -d "$DEST"
echo "[+] 完成，源码目录: $DEST/Code_Opensource"
ls -la "$DEST/Code_Opensource" | head
rm -rf "$WORK"