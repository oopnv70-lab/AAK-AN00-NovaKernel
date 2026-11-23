# 荣耀 WIN RT（AAK-AN00）官方内核/开源代码

## 机型
- 名称：荣耀 WIN RT
- 型号：AAK-AN00
- 系统：MagicOS 10.0（Android）
- 发布：2025 年 12 月

## 开源代码条目（荣耀开源发布中心）
- 文件名：`AAK-AN00_MagicOS10.0_Opensource.zip`
- 大小：约 550 MB（fileLen 562995.2 KB）
- 发布日期：2026-01-29
- knowledgeId：`en-gb15893765`

## 关于下载链接「会过期」
荣耀给出的 `fileUrl` 形如：

```
https://iknow-dl.service.hihonor.com/ctkbfm/servlet/download/downloadServlet/<签名token>.zip
```

它是 **动态签名链接**：
1. 带时效，存下来的链接迟早失效；
2. 有防盗链，裸请求（无 Referer/会话）会返回 403。

所以**不要存这条死链接**。长期该记录的是「可复现的定位信息」：
- 入口页：https://www.honor.com/global/opensource/
- 接口：`POST/GET https://selfservice-cn.hihonor.com/ccpcmd/services/dispatch/secured/CCPC/EN/tkb/findDocKnow/1000`
- 参数：siteCode=worldwide, regionCode=GB, offeringCode=CMCG10000045(Mobile Phone), knowledgeTypes=F34, fileType=openSourceSoftware

每次需要链接时，实时查接口重新生成一个「当时有效」的 URL 即可（见 `src/get_opensource_link.sh`，只打印链接、不下载、不落本地）。

## 用法
```bash
bash src/get_opensource_link.sh AAK-AN00
```
输出当前有效的 fileUrl（及文件名/大小/日期）。拿到后由使用者自行决定是否下载。