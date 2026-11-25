# Shop_app 交接

## 2026-11-25：Commerce V2 收藏、商品提醒與通知

分支 `feat/commerce-v2-specs`，依據 figura-api `docs/ENGAGEMENT_API.md`（V27）。只修改 figura-app；未新增套件或變更購物車／結帳／訂單流程，figura-api 與 figura-web 未修改。

- `lib/features/engagement.dart` 沿用 `RequestView`、`infoCard`、`WriteButton` 與既有 Bearer `request`：商品詳情登入後讀 `favorites/ids` 與 `product-alerts`，愛心 PUT／DELETE、顯示已訂閱種類、bottom sheet 勾選四種提醒後 PUT 整組（空陣列取消）。訪客顯示「登入後才能收藏」與前往登入，不儲存訪客收藏。
- 會員頁新增「我的收藏」、「通知設定」、「通知（API unread 則未讀）」；收藏／通知列表每頁 20 筆、捲動載入、阻擋重複載入、失敗顯示重試、可下拉重讀。收藏顯示 API 價格與可售狀態、移除及進商品頁；未提供價格時顯示待確認。通知未讀標題加粗、單筆與全部標已讀，收到 ACK 後依 productId／orderId／preorderOrderId 進既有詳情；無目標只更新已讀。
- 通知偏好三個開關每次送完整布林欄位與 `expectedVersion`；409 顯示「設定已在其他裝置變更」並重讀；顯示 Email 驗證與測試環境不實際寄信說明，註明偏好只控制 Email、站內通知保留。新功能寫入沿用 `Writes` 安全儲存與未完成操作隔離；不盲目重送未知結果，`PendingBanner` 針對新資源讀取目前伺服器資料供核對。ACK 後讀取失敗僅提供重讀。
- 新增 `test/engagement_test.dart` **14 項 widget 測試**，沿用 `test/api_test.dart` 的 Adapter／response，涵蓋愛心方法與路徑／Bearer、訪客提示與登入導向、提醒整組替換與清空、偏好 409 重新讀取版本與未知結果保留、收藏捲動分頁／失敗重試／移除／商品導向、通知單筆與全部已讀／字重／三種目標導向／分頁／失敗重試、會員未讀數入口。
- 驗證：repo 內 `work/flutter` 的 `dart format lib test` 通過；`flutter analyze --no-pub` **No issues found**；`flutter test --no-pub --timeout 60s` **51 通過、2 項既有 opt-in live 測試略過**；`flutter build web --release --no-pub` 成功。未連線資料庫，未執行真後端通知掃描／Email／真機／Android／iOS 驗證；Email 是否實際啟用由伺服器 `emailDeliveryActive` 決定。
- 本次依指示只做本機 commit（訊息結尾 `Co-Authored-By: Codex`），不 push、不開 PR。開始時工作樹乾淨、HEAD `bea7f40`，已讀本機 `origin/main:docs/HANDOFF.md` 並核對 status/log/diff。`git fetch origin` 因 `.git/FETCH_HEAD` 寫入被拒失敗，`git ls-remote` 亦無法連線 GitHub 443；無法確認遠端最新狀態，未更新 main。

## 2026-11-25：Commerce V2 商品規格與後端搜尋

分支 `feat/commerce-v2-specs`，依據 figura-api `docs/CATALOG_SEARCH_API.md`（V25／V26）。僅修改 figura-app；未新增套件、未變更購物車／結帳／訂單寫入。

- 商品詳情沿用 `RequestView`／`infoCard`，新增「商品規格」表格，只顯示有值欄位，翻譯比例／材質／類型／版本代碼，配件逐項列出；`AI_CONCEPT` 顯示「AI 虛構展示商品」，概念材質只列於「設定材質（概念）」，不混入真實材質。商品詳情與列表顯示 API 可售狀態、預購截止與到貨區間；列表價格使用 `minPriceTwd`。
- 「現貨」分頁改用公開 `catalog/products` 後端搜尋：送出才套用 q、五種排序／有關鍵字時可選相關度、bottom sheet 多值篩選與限定／整數價格區間。`catalog/facets` 隨 q 與草稿條件重讀選項及筆數（依契約排除 availability、sort、分頁）；取消不套用，清除同時清空價格。每頁 20 筆，捲動載入後續頁、顯示總筆數與失敗重試；條件切換回第 1 頁及頂端，阻擋重複／超過末頁請求，忽略舊條件延遲回應。預購分頁保留原本流程。
- 新增 `test/catalog_search_test.dart` 10 項 widget 測試，沿用 `Adapter`／`response`：有值規格及代碼翻譯、概念材質隔離與預購時程、舊商品缺規格、送出搜尋／相關度、多值篩選與 facets 契約、完整條件第 2 頁、連續捲動不重複載入、條件重設、延遲回應隔離、價格驗證／取消、清除價格、三種狀態標示（部分情境合併於同一測試）。
- 本機 Windows／repo 內 `work/flutter`：`dart format lib test` 通過；`flutter analyze --no-pub` **No issues found**；`flutter test --no-pub --timeout 60s` **37 通過、2 項既有 opt-in live 測試略過**；`flutter build web --release --no-pub` 成功。網路限制使一般依賴解析停滯，使用既有快取，未變更 `pubspec.yaml`／lock。未連線資料庫、未執行真後端／真機／Android／iOS 驗證。
- 依本次指示只做本機 commit，不 push、不開 PR。開始時工作樹乾淨，HEAD 與本機 `origin/main` 同為 `0d518b2`；已讀本機遠端追蹤版交接。`git fetch origin` 因既有 `.git/FETCH_HEAD` 寫入被拒失敗，另以 `ls-remote` 核對時 GitHub 443 無法連線，因此無法確認遠端最新狀態；未更新 main。


## 2026-11-18：Phase 5 配送

分支 `feat/shipping`。需要後端 V23。結帳（購物車）可選宅配／超商取貨（測試門市）、分開寄／一起寄，切換時重新向伺服器報價，送出帶配送欄位；訂單詳情新增「配送」卡（方式、狀態、門市或地址、包裹運費、合併寄送、測試貨件號）。`flutter analyze` 無問題、`flutter test` 27 通過（2 項 live 略過）；`unified_cart_test` 涵蓋超商＋一起寄，`preorder_deposit_test` 涵蓋配送卡。

## 2026-11-18：Phase 4 預購訂金／尾款、延期

分支 `feat/preorder-deposit`。需要後端 V22。批次頁顯示付款方式；直接預購與統一結帳顯示訂金／尾款；預購詳情新增「訂金與尾款」卡、到貨時程異動、付款按鈕標示訂金或尾款與金額（金額由伺服器決定）；訂單列表待付尾款提示（已退款不提示）。`test/preorder_deposit_test.dart`；`flutter analyze` 無問題、`flutter test` 27 通過（2 項 live 略過）。

## 2026-11-18：Phase 3 統一購物車與結帳

分支 `feat/unified-cart`（疊在 `feat/order-center` 上）。需要後端 `feat/unified-cart`（V21）。

- 預購批次頁新增「加入購物車」（登入後），保留「直接預購下單」。
- 購物車分現貨與預購兩區（預購可增減／移除、顯示批次、預估到貨與剩餘名額），合計使用 `totalTwd`，`checkoutReady` 才能結帳。
- 結帳（`/checkout/stock` 路由沿用）改讀 `checkout/quote` 分組顯示，下單 `POST /mobile/customer/checkout`（`expectedTotalTwd`），一張訂單到詳情、多張到訂單中心；未確認操作重試也處理多張回應；購物車寫入的核對清單包含預購。
- 測試：`test/unified_cart_test.dart`（混合購物車、分組、送出內容不含舊欄位、多張導向訂單中心、不呼叫舊下單 API）；`flutter analyze` 無問題、`flutter test` 26 通過（2 項 live 預設略過）；live socket（本機後端、私有可拋棄 fixture `work/live-fixture-p3.json`）2 項通過，含真實統一結帳。

## 2026-11-18：Phase 2 統一訂單中心

分支 `feat/order-center`（疊在 `feat/contact-only-login` 上），需要後端 `feat/order-center`。

- 「訂單」分頁改用 `order-center`：全部／現貨／預購切換、狀態與排序下拉，伺服器端分頁；卡片顯示「現貨訂單／預購訂單 · 階段」、標題、件數、金額、付款期限、預計到貨。點選仍進原本的現貨／預購詳情（付款、取消不變）。
- 測試：`flutter analyze` 0 issue、`flutter test` 25 通過（新增 `order_center_test.dart`）；live 測試對本機後端通過（新增 order-center 檢查）；`smoke_browser.cjs` 改用新標題格式（未實跑）。

## 2026-11-18：配合後端「只用手機＋Email」（contact-only-login）

分支 `feat/contact-only-login`，需與 figura-api `feat/contact-only-login`（jackteng-dev/figura-api#10）一起上線；**App 先上或同時上**，否則舊版 App 註冊與修改暱稱會失敗。

- **註冊**：手機＋Email＋密碼（移除帳號名稱與顯示名稱）；註冊後以 Email 自動登入。400／409 顯示伺服器說明（例如 Email／手機已被使用），5xx／斷線維持通用訊息。
- **登入**：欄位「手機或 Email」；`lib/core/identity.dart` 的手機／Email 正規化與後端 `CustomerPayloads` 規則一致，送出正規化值；401 一律「手機／Email 或密碼不正確」。
- **會員中心**：顯示 Email、驗證狀態、手機；移除修改暱稱；頁首顯示「會員中心」，不顯示系統產生的 `username`／`displayName`。驗證信目前為測試環境模擬、不會真的寄出，所以只顯示狀態。
- **舊版殘留**：升級前留下的「修改暱稱」待核對操作只能重讀核對後解除，不會再送 PATCH。
- **綠界**：付款清單 `provider=ECPAY`（網站發起的綠界測試付款）在 App 只顯示、不提供模擬成功／失敗（後端也會拒絕）。
- **不變**：Bearer／refresh 輪替／secure storage／pending UUID 機制、`storage.dart`、`Writes` 未改；`pubspec.lock` 未變。
- **測試（本機 Windows，Flutter 3.47.6 同 CI 釘選 commit，SDK 在忽略的 `work/flutter`）**：`dart format` 無變更；`flutter analyze` 0 issue；`flutter test` 24 通過、2 個 opt-in live 測試 skip（新增 `test/contact_login_test.dart` 11 項）。對本機隔離後端（figura-api `feat/buy-now` 建置＝含 contact-only-login，隔離 demo DB）：`live_socket_test` 2 項通過（新增「手機＋Email 註冊、重複 409、Email 大寫登入、refresh 輪替、修改暱稱 403、登出清除 refresh、手機重新登入、內部帳號名稱 401」，原有購物／預購／付款流程）；debug browser harness `smoke_browser.cjs` 11 項 UI 通過；`flutter build web --release` 成功。
- **發布前檢查（同日）**：版本升到 `0.2.1+4`（公開 `sandbox-latest` 為 0.2.0+3）。在本分支手動執行 `android-sandbox-apk.yml`（run 44262631768）：Linux 上 format／analyze／test 通過、APK 建置成功、**publish 步驟 skipped**，`sandbox-latest` 未變（仍為 2026-11-10、59f041d）。Artifact 靜態檢查：SHA256 相符、package `dev.jackteng.figura`、versionCode 3→4、v2 簽章憑證與公開版相同（可覆蓋升級）、3 個 ABI、內建沙盒 API。新版 App 對目前 figura-api **main** 後端 live 測試也通過（註冊、409、Email 登入、refresh、登出、手機重新登入、購物），所以 App 可以先於後端上線。Release 說明與 README 示範帳號改為 Email `demo-customer@example.com`（需伺服器每日重置種子配合）。**APK 未安裝到任何裝置或模擬器。**
- **未做**：本機沒有 Android SDK，**未建置 APK、未跑 Android 模擬器／原生 `verify_android.py`**（已改用新欄位，未實跑）；iOS 未驗證。本 repo 沒有 PR 自動 CI（只有手動、會發布 sandbox APK 的 workflow，未觸發）。

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
