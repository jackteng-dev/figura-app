# Shop_app 交接

更新：2026-10-07。獨立私人 Flutter 倉庫，第一版會員／購物／現貨與整筆預購流程已實作。共用 shop_bak_ap 後端，新 native Bearer 入口，沒有另開資料庫或複製業務服務；Shop_back Vue網站／員工後台保留。尚未真機、iOS build、正式簽章／上架與營業。

## 完成內容

Flutter 3.47.6 / Dart3.13.5，Riverpod + Dio + GoRouter + Flutter Secure Storage，Android/iOS runner與繁中字型；pubspec.lock與版本固定。Android INTERNET/備份關閉、release HTTPS、debug loopback/emulator exception限定；iOS不放寬ATS。

- 會員註冊／登入／本裝置登出，access記憶體、refresh/device UUID原生secure storage；單一refresh更新、401只重試一次，無一般network自動重送、慢refresh在登出後不恢復登入。
- 現貨商品／款式／品牌／分類／主圖、預購批次／名額／截止與到貨區間；公開分頁、loading/error/retry/empty state、底部導航。
- 版本購物車数量增減／移除、本人地址新增編輯刪除／驗證、現貨与預購結帳／伺服器報價核對；本人訂單分頁、取消與模擬付款成功／失敗、現貨配送／退款退貨與預購到貨分配／出貨／送達安全進度。預購與現貨resources分開。
- 未確認寫入安全保存原owner/UUID/body並凍結新寫入；restart與原owner再登入仍可核對，UUID操作只重試原操作、cart/address/profile/現貨取消先讀目前狀態由人核對；ACK後GET失敗不能重送。

## 驗證

- `flutter analyze` 無issue、dart format；10個session/network/pending行為測試與3個widget測試通過，預設另1個live socket測試明確skip。live socket以私有fixture啟用後另**1項完整真API測試通過**，包含原生登入、cart/address、現貨與預購結帳/payment/replay/list/refresh/logout。
- Flutter debug browser harness（390×844）**11項實際UI流程通過**：登入、商品加入、版本數量更新、現貨結帳／付款、預購結帳／付款／arrival progress、地址表單、歷史導航、登出及無uncaught error。harness使用MemoryStore、只測試，不代表原生Keychain/Keystore或真機。
- Android **debug APK** 與 **unsigned release APK** 成功。release以明確示範HTTPS shop.example 編譯，不是可用的正式API或部署；apksigner核對無簽名，不能直接安裝／上架。APK SHA、SDK、source SHA及safe證據見 verification/customer-app-2026-10-07.json，产物／SDK／rawlogs留ignored work/build。
- 後端完整 Maven **262項：260通過、2既有歷史fixture略過、0failure/error**；新增6個真MySQL/Redis原生身分整合，新 HTTP19、網站舊合約HTTP153；原生 API restart／Redis outage／mock flags結果見後端同份safe證據，schema仍V18。Redis預設60秒等待超過App deadline，已補connect/command預設2秒並重跑完整測試與故障演練。
- 字型缺字與Flutter瀏覽器semantics測試選取已修正。初次SDK/Gradle下載缺proxy/CA導致失敗，依本環境繼承proxy與私有truststore修正，未關閉TLS驗證；本機不同環境不要複製本雲端proxy設定。

## 重要檔案

lib/core/api.dart（session／Writes）、models/storage/providers，lib/app.dart（router／shell／待核對操作），features/auth/catalog/shopping/orders/common，native runner/network config，tests與test_support/browser_main.dart、scripts/smoke_browser.cjs／serve_harness.py，API與裝置待驗文件。SDK/密碼/fixture/截图/依賴/build不進Git。

## 保存與下一步

GitHub createRepository最初權限不足，使用者建立並提供空私人 Elpsy-Deng/Shop_app；已核對空遠端並接入 origin，初次無遠端HANDOFF。完成驗證/交接後推main；後續先fetch讀遠端HANDOFF，status/log/diff、ff-only、不force。

下一步是 Android真機安装／Keystore／背景恢復／斷網與更新、macOS Xcode iOS build／Keychain／签名及平台驗收，詳 CLOUD_LOCAL_FOLLOWUP。正式API域名／HTTPS、商店帳號／正式簽章、品牌App icon／真provider／會員安全仍待環境或商家驗收。原整筆預購MVP已完成；訂金尾款、延期、部分退款是選擇性擴充，不默默加作開發完成條件。

沒有實際收款、物流、寄信、推播或上架，不改其他作品或原DB。後端測試scope只自己的新空demo，收尾停止 owned API/harness、移除該scope容器／資料volumes；clean Git與實際遠端以本輪收尾核對。

收尾驗證補充：最終 API 程序重啟／mock 關閉／Redis故障與重啟 **10項通過**，Redis驗證等待設為2秒逾時，故障回覆503；Redis清空後舊pair拒絕，重新登入才恢復。資料庫 **37項業務invariant皆0**，history18，V1–V18 byte不改；保留合法PAID／待到貨的合成訂單，不把待到貨清零當業務條件。最終Maven262／Flutter13（另live1）／UI11／native HTTP19／website HTTP153／Vue production build通過，詳safe JSON。
