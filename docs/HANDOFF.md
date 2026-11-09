# Shop_app 交接

更新：2026-10-08。獨立私人 Flutter 顧客 App 第一版已完成；本輪完成 Android 模擬器原生核心驗收與可安裝測試 APK 0.1.1+2，補商家正式簽章設定及 iOS Keychain entitlement。仍共用 shop_bak_ap 後端；Shop_back Vue 網站及員工後台保留。實體手機、iOS build、商家正式簽章／上架與正式營業尚未完成。

## 已實作的顧客流程

Flutter3.47.6／Dart3.13.5、Riverpod／Dio／GoRouter／Flutter Secure Storage。會員註冊登入／本裝置登出、現貨及預購商品／主圖、版本購物車、本人地址、結帳／模擬付款、本人訂單／取消、退款退貨及到貨／配送安全進度。現貨與預購各自資源，共用後端，不複製業務服務或另開產品資料庫。

access 僅記憶體，refresh/device/pending 僅原生安全儲存。未知寫入保留原 owner／UUID／body、凍結新寫入；UUID 操作只重試原操作，版本寫入先讀核對，不盲目重送。ACK 後讀取失敗只重讀。原第一版的實作、真 Dart socket／browser harness 及後端故障證據見[2026-10-07 歷史交接](verification/customer-app-handoff-2026-10-07.md)。

## 本輪原生驗收

- Android29 x86_64 模擬器、真 NativeStore／AndroidKeyStore 加密偏好儲存與真 Spring／MySQL／Redis API。seed／resume／version／resolve **4 個核心階段通過**：程序重開保留 device／refresh 輪替與原顧客；已提交訂單回覆遺失後保留原 UUID/body，兩次請求得到同一單；ACK 後 GET503 不恢復待寫操作；版本購物車回覆遺失只送一次，不同顧客不接管原 pending，原顧客再登入讀取核對。偏好檔沒有本輪觀察到的明文 access／refresh／device 值。不能據此宣稱實體硬體安全儲存已驗收。
- 最終正式入口 debug APK 覆蓋更新、帳戶／冷啟動／HOME 背景返回／登出及登出後重開，**8 項手動畫面／生命週期檢查通過**；ADB 操作、實際畫面逐一查看，登出前後原生 secure refresh 欄位另外核對。核心階段與手動檢查分開計數，safe JSON 的10個核心群組不膨脹為個別子測試總數。
- **完整 UI 自動化未通過**：軟體模擬器 System UI ANR 遮住 selector，續跑 UiAutomator dump45秒逾時。Skia override 的 HOME 返回持續黑畫面，該情境不算 UI 通過；最終預設 renderer 背景返回曾短暫黑畫面，之後畫面確認恢復原帳戶。無 KVM 的環境不能用來判定實體手機效能；真機須覆驗預設 renderer。

## 建置及回歸

- dart format 無變更，`flutter analyze` 無 issue，unit/widget **13 通過、1 預設 live socket skip**。本輪未重跑 live socket 與 browser harness；前輪 live1／browser11／website HTTP153 屬歷史證據。
- Android debug 與 unsigned release 建置成功。Gradle 改2GiB heap／2 workers，避免8GiB雲端環境同時建置及模擬器造成 OOM；建置與装置測試順序執行。
- 正式簽章讀 ignored `android/key.properties`：缺檔產 unsigned、部分欄位直接拒絕，完整設定使用商家 key。部分設定拒絕及完整路徑以拋棄式開發 key 驗證成功，並已移除設定、恢復 unsigned release；未提供商家 key，不宣稱正式簽章完成。
- iOS own-app Keychain entitlement 已套 Debug／Profile／Release；plist 靜態解析通過，ATS 未放寬，最低iOS15。Linux 沒有 Xcode，**未做 iOS build 或 Keychain 執行驗證**。
- 專用新空 elpsy-app-device-20261008 scope：後端完整 `mvn package` **262 項：260 通過、2 既有 fixture skip、0 failure/error**；原生真 HTTP **19 通過**；資料庫 **39 項 invariant 全0**、Flyway history18、V1–V18 bytes 不變；Vue `npm run build`（vue-tsc／Vite）成功。後端及 Vue 產品程式本輪未變更。

## 測試 APK 與安裝

已交付[私人草稿測試版本](https://github.com/jackteng-dev/Shop_app/releases/tag/untagged-2e7d99bc1f7c451ca04d)（tag `v0.1.1-device-test`），檔案 `ELPSY-Shop-0.1.1-android-test.apk`；需登入有權限的GitHub帳號。版本0.1.1／code2，com.elpsy.elpsy_shop，Android7/API24以上，arm32／arm64／x86_64，開發簽章。

原雲端APK附件上傳端點401；改以手動GitHub Actions從提交 `02beccc7facebfce377b5ec76d749bbbadc32484` 重建，format／analyze／test／build／artifact／私人草稿上傳步驟均成功。[建置紀錄](https://github.com/jackteng-dev/Shop_app/actions/runs/37712548885)，備用Actions artifact保留至2026-10-22。沒有啟用付費或公开發布。下載回來的交付檔 **180297725 bytes**、開發簽章／版本／3 ABIs確認，SHA256與GitHub server digest及附檔SHA256SUMS一致：

`4ac11c22115f0c073b91247f8fe1e42e26aef18fa1a07b0bc447f320899f06d1`。

**證據分開**：上文原生核心4階段／手動UI8項屬已驗收的雲端原APK（180300193 bytes，SHA256 `9640f0c154a99f80a02d2e9d670f36777ec2dec73ae9bd168cd5be3d1cab3b43`）；實際交付是同產品原始碼的CI重新建置檔，簽章／SHA不同，**尚未做裝置測試**。新簽章不能直接更新原雲端開發簽章APK，先核對測試資料及憑證，不自動卸載。

API `http://127.0.0.1:9090/ELPSY/api/` 需要手機 USB adb reverse 連使用者電腦自己的隔離 demo。APK 沒有會員帳密、不連目前雲端測試後端。unsigned release 的 shop.example 僅編譯示範，不能安裝或視為部署。詳[安裝、原生重跑、正式簽章及 Mac iOS 步驟](DEVICE_ACCEPTANCE.md)。

## 重要檔案與證據

lib/core/api.dart／storage.dart、lib/app.dart、features；本輪 test_support/native_main.dart、scripts/verify_android.py、android/app/build.gradle.kts／gradle.properties、ios/Runner/Keychain.entitlements／project.pbxproj、DEVICE_ACCEPTANCE、CLOUD_LOCAL_FOLLOWUP。safe證據：[customer-app-device-2026-10-08.json](verification/customer-app-device-2026-10-08.json)。SDK／fixture／帳密／token／原始日誌／畫面／APK 留 ignored work/build；只交付產品入口測試APK，不交付native probe或測試key release。

## 下一步與收尾

下一步是實體 Android USB 安裝，覆驗預設 renderer、背景／冷啟動、斷網／未知結果、同簽章更新及 Keystore；iOS 需 Mac／Xcode、Apple Team 與有效 HTTPS 測試API。正式域名／部署、商家 Android key／平台帳號、真 provider／政策及營運另待驗收。整筆預購 MVP 已完成；訂金尾款、延期、部分退款仍選擇性擴充，不默默加作 MVP 必要條件。

本輪先 fetch／遠端交接／status/log/diff／ff-only，以三倉庫各自 main 保存、不 force。僅封存自己1商品／關閉1批次，停止自有API／controller／模擬器，移除專用3容器／2 volumes／network，核對23306／27379／28333／29092／29102皆關閉；未操作原DB、其他作品或真人訊息。付款／配送／退款／通知仍mock。
