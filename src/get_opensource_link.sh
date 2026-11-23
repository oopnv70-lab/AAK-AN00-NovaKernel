#!/bin/bash
# 荣耀开源发布中心 —— 只取「当前有效」的签名下载地址（不下载文件、不落本地）
#
# 背景：
#   fileUrl 形如 .../downloadServlet/<签名token>.zip，是动态签名链接，会过期，
#   直接保存的链接迟早失效；因此不去存"死链接"，而是每次实时查官方接口，
#   重新生成一个当前有效的 URL 打印出来。这样"链接过期"的问题就消解了。
#
# 稳定定位信息（这才是长期该记录的）：
#   型号/文件名   : AAK-AN00_MagicOS10.0_Opensource.zip   (荣耀 WIN RT)
#   knowledgeId   : en-gb15893765
#   offeringCode  : CMCG10000045   (Mobile Phone)
#   knowledgeTypes: F34            (openSourceSoftware)
#   入口页         : https://www.honor.com/global/opensource/

set -u
MODEL_CODE="${1:-AAK-AN00}"
API='https://selfservice-cn.hihonor.com/ccpcmd/services/dispatch/secured/CCPC/EN/tkb/findDocKnow/1000'
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
URL=''; FN=''; SZ=''; DT=''; TOTAL='?'
for p in $(seq 1 8); do
  curl -sG -A "$UA" --max-time 45 "$API" \
    --data-urlencode 'jsonp=cb' --data-urlencode 'siteCode=worldwide' \
    --data-urlencode 'regionCode=GB' --data-urlencode "curPage=$p" \
    --data-urlencode 'pageSize=50' --data-urlencode 'offeringCode=CMCG10000045' \
    --data-urlencode 'channelCode=10005' --data-urlencode 'countryCode=0' \
    --data-urlencode 'country=0' --data-urlencode 'langCode=en-gb' \
    --data-urlencode 'language=en-us' --data-urlencode 'knowledgeTypes=F34' \
    -o "$TMP/p.txt"
  resp=$(python3 - "$TMP/p.txt" "$MODEL_CODE" <<'PY'
import json,re,sys
t=open(sys.argv[1],encoding='utf-8',errors='ignore').read()
code=sys.argv[2]
m=re.search(r'cb\((\{.*\})\)', t, re.S)
if not m: print(''); sys.exit()
o=json.loads(m.group(1)); rd=o.get('responseData',{})
print('TOTAL', rd.get('totalCount'))
for it in rd.get('rList',[]):
    if code in it.get('fileName',''):
        print('URL', it['fileUrl']); print('FILE', it['fileName'])
        print('LEN', it['fileLen']); print('DATE', it['releaseDate']); break
PY
)
  t=$(echo "$resp" | awk '/^TOTAL/{print $2}'); [ -n "$t" ] && TOTAL="$t"
  URL=$(echo "$resp" | awk '/^URL /{print $2}')
  [ -n "$URL" ] && { FN=$(echo "$resp" | awk '/^FILE /{print $2}'); SZ=$(echo "$resp" | awk '/^LEN /{print $2}'); DT=$(echo "$resp" | sed -n 's/^DATE //p'); break; }
  np=$(python3 -c "import math;print(math.ceil($TOTAL/50))" 2>/dev/null || echo 99)
  [ "$p" -ge "$np" ] && break
done

if [ -z "$URL" ]; then echo "[x] 未找到 $MODEL_CODE"; exit 2; fi

echo "FILE : $FN"
echo "SIZE : ${SZ}KB   DATE: $DT"
echo "URL  : $URL"
echo "---- 下载提示：该链接有时效且做防盗链，需带 Referer 才能下：----"
echo "curl -L -A \"$UA\" -e https://www.honor.com/global/opensource/ \"$URL\" -o $FN"