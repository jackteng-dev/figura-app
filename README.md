# ELPSY Shop 顧客 App

獨立 Flutter Android／iOS 顧客端。商品、現貨／預購交易與進度共用 [shop_bak_ap](https://github.com/jackteng-dev/shop_bak_ap)；[Shop_back](https://github.com/jackteng-dev/Shop_back) 保留 Vue 網站與員工後台。

第一版：註冊／登入／裝置登出、商品與預購批次、購物車、收件地址、現貨／整筆預購結帳、模擬付款、本人現貨／預購訂單、到貨分配／出貨／送達與退款／退貨進度。付款與配送目前為 mock，沒有實際收款、物流或推播。

Flutter **3.47.6**／Dart **3.13.5**，依賴版本與 pubspec.lock 固定。Riverpod 管理 API／session／寫入狀態、GoRouter 導航、Dio 請求、Flutter Secure Storage 使用原生 Keychain／Keystore。API 與平台注意事項見 [交接](docs/HANDOFF.md)、[API與安全](docs/API.md)、[裝置安裝與驗收](docs/DEVICE_ACCEPTANCE.md)、[正式環境待驗](docs/CLOUD_LOCAL_FOLLOWUP.md)。

## 開發

先啟動後端的全新隔離 demo；設定與資料不放入 App。Android Studio 安裝 SDK，iOS 需要 macOS／Xcode。App 無預設正式伺服器，不把 localhost 或示範域名当成部署。

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:29092/ELPSY/api/
```

Android emulator 的 10.0.2.2 指向開發主機；手機可使用可達的 HTTPS API，或依裝置文件以USB adb reverse連到本機demo。只有 debug 且已知 loopback／emulator host 可以 HTTP；release 只接受 HTTPS。開發時用私有 `work/` 設定，不把帳號密碼放命令列或 Dart 原始碼。

```sh
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:29092/ELPSY/api/
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_HOST/ELPSY/api/
```

本倉庫支援忽略的 `android/key.properties` 載入商家自己的keystore；未提供時release產物仍為 **unsigned**，不能直接安裝／上架，欄位不全會失敗。Android INTERNET 已配置、備份關閉；iOS Keychain entitlement已配置，未放寬ATS。iOS 程式已建立，Linux 無法驗證 iOS build。實際驗證結果見交接，不將 APK compile 等同真機測試。

## 可重跑驗證

`flutter test` 包含 10 個網路／session／未確認操作測試與 3 個 widget 測試；實際 loopback 測試預設 skip。後端 `scripts/smoke_mobile.py --fixture <本倉庫>/work/live-fixture.json` 只在自己的 disposable demo 產生合成資料與私有設定，再執行：

```sh
flutter test test/live_socket_test.dart --dart-define-from-file=work/live-fixture.json
```

另有 **debug-only** Flutter browser harness（記憶體 token、不持久化）驗證手機尺寸 UI，並不替代 Android/iOS 裝置測試，也不是 Vue 替代品：

```sh
flutter build web --debug --no-wasm-dry-run -t test_support/browser_main.dart
python3 scripts/serve_harness.py
node scripts/smoke_browser.cjs
```

測試 server 只綁127.0.0.1:25178，代理同機29092後端；需要本機 Playwright／Chromium，透過 PLAYWRIGHT_MODULE_PATH／PLAYWRIGHT_CHROMIUM_PATH 指向安裝路徑。只有忽略的 work 存 fixture／screenshots／原始日誌；safe evidence 不包含帳密或收件資料。

原生Android可透過 `test_support/native_main.dart` 與 `scripts/verify_android.py` 驗證 NativeStore、程序重啟、已提交但回覆遺失、版本操作核對、owner隔離、App更新與真正帳戶UI。詳裝置文件；probe僅供專用debug測試裝置，不以probe作交付入口。

繁中字型 Noto Sans TC 使用 SIL Open Font License，來源、SHA、完整授權見 [字型資訊](assets/fonts/README.md)。
