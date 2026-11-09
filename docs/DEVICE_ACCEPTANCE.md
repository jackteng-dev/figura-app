# Android 安裝與 iOS 建置交接

更新：2026-10-08。使用自己的隔離 demo 與合成會員；mock 不會真正收款或寄送。各項是否通過以本輪 verification JSON 與 HANDOFF 為準。

## Android USB 測試 APK

測試版為 `com.elpsy.elpsy_shop`、Android 7.0 / API24 以上，支援arm32、arm64與x86_64，開發簽章、debug 模式，版本0.1.1／build2。交付 APK 連到 `http://127.0.0.1:9090/ELPSY/api/`，需要 USB 的 adb reverse 將手機連到你電腦上的後端；安裝檔內沒有會員帳密。這個位址不是雲端部署，也不會連到目前 Codex 的私有測試後端。

1. 在你的電腦依 [後端 NEW_MACHINE_SETUP](https://github.com/jackteng-dev/shop_bak_ap/blob/main/docs/NEW_MACHINE_SETUP.md) 啟動新的獨立 demo，確認 API 埠為9090。使用私人 env；不要以既有正式 DB 做測試。
2. 手機開啟開發人員選項、USB 偵錯，以 USB 接到同一台電腦，允許這台電腦的偵錯連線。Android SDK Platform Tools 要可執行。
3. 找出指定手機的序號，將下面 `YOUR_SERIAL` 換成它，`APP.apk` 換成下載的測試 APK。`-r` 保留同簽章既有 App 資料；不同簽章安裝會失敗，需要先處理舊 App 與測試資料，不要自動解除安裝。

```sh
adb devices -l
adb -s YOUR_SERIAL reverse tcp:9090 tcp:9090
adb -s YOUR_SERIAL install -r APP.apk
adb -s YOUR_SERIAL shell am start -n com.elpsy.elpsy_shop/.MainActivity
```

若電腦後端使用29092，改為 `adb -s YOUR_SERIAL reverse tcp:9090 tcp:29092`。USB 重新連接或手機重開後可能需重做 reverse。驗收完移除：`adb -s YOUR_SERIAL reverse --remove tcp:9090`。

若要離開 USB 測試，先取得手機可達、憑證有效的 HTTPS API，再用正式入口重新編譯；不要改成允許任意明文 HTTP：

```sh
flutter build apk --debug --dart-define=API_BASE_URL=https://YOUR_HOST/ELPSY/api/
```

## GitHub Actions 重建測試版

`.github/workflows/android-test-apk.yml` 只由手動 `workflow_dispatch` 啟動，固定 Flutter3.47.6 commit、Java21、lockfile與localhost9090；先format/analyze/test，再build debug APK。產物保留14天，並嘗試附到**既有私人草稿** v0.1.1-device-test，不建立公開正式release。無商家key或私人fixture。`BUILD.txt`記錄實際source/run，`SHA256SUMS.txt`核對下載檔。

GitHub Actions使用自己的新開發簽章，與本雲端已驗收APK簽章可能不同；安裝更新應核對憑證，不能自動刪既有資料。重新建置APK的SHA也不同；本輪Android原生證據只屬JSON記錄的雲端原檔，不能把CI重建檔寫成已跑過裝置測試。當連線token不能上傳Release附件，Actions下載產物可作替代；GitHub需有可用免費Actions額度，沒有額度則保留原始碼及本機建置步驟，不啟用付費。

## 原生驗收重跑

`test_support/native_main.dart` 是僅供 debug、loopback 的原生測試入口，使用真 NativeStore。`scripts/verify_android.py` 只控制 `--serial` 指定裝置，但會清除此測試裝置上本 App 資料，因此只在專用測試裝置跑。

後端先啟動全新隔離 demo，埠29092；透過後端 `scripts/smoke_mobile.py` 產生忽略的 `work/device-fixture.json`，不可提交或分享。controller只綁127.0.0.1:29102，將請求送往同機29092；消耗伺服器成功回覆後切斷 client socket，演練已提交但ACK遺失，並模擬ACK後GET503。

```sh
flutter build apk --debug -t test_support/native_main.dart \
  --dart-define=API_BASE_URL=http://10.0.2.2:29102/ELPSY/api/
cp build/app/outputs/flutter-apk/app-debug.apk work/native-probe.apk
flutter build apk --debug --build-number=2 \
  --dart-define=API_BASE_URL=http://10.0.2.2:29102/ELPSY/api/
cp build/app/outputs/flutter-apk/app-debug.apk work/app-emulator.apk
python3 scripts/verify_android.py --serial emulator-5554 \
  --fixture work/device-fixture.json --probe-apk work/native-probe.apk \
  --app-apk work/app-emulator.apk --output work/android-acceptance.json
```

腳本驗證 force-stop 冷啟動、Keystore 加密的 refresh/device/pending 持久化、UUID/body原样重試、版本寫入只讀核對、不同owner隔離、正式入口APK覆蓋更新、真正帳戶UI、HOME背景返回、登出後重開。測試版 probe 的刻意降版安裝只用於專用debug裝置的最後儲存檢查，不用於正常產品更新。API_LEVEL、APK SHA與故障結果存safe JSON，帳密/token不存驗收證據。Android模擬器不代表實體手機或安全硬體已驗收。

若改用上述交付APK（localhost9090），腳本加 `--reverse-app-port=9090`，將指定裝置9090代理至本輪controller29102；收尾移除此映射。無KVM的軟體模擬器可降低解析度／動畫負載，必要時加 `--no-impeller` 使用Flutter的debug renderer override；這種結果須記錄，不能推論正式手機Impeller、硬體Keystore或效能已通過。正常手機不要套用雲端SDK的proxy／私有CA設定。

腳本遇到Android自身的 `System UI isn't responding` 對話框可選Wait，最多10次並記錄 `systemUiAnrRecoveries`；不自動處理ELPSY App的ANR。核心四階段完成後保存 `<output>.core.json`；若只有後續UI被環境遮擋，可保留同一裝置／App資料，以 `--resume-core=<core.json>` 接續UI，會核對兩份APK SHA與裝置序號。重開新裝置或清除App資料需重跑核心驗收。此種證據須明示分階段續跑，計數可能包含「已通過的核心階段」群組，不能宣稱每個子檢查都重新執行。

## Android 商家正式簽章

已支援忽略的 `android/key.properties`。使用商家自行保管的私有 keystore；不要把 keystore、密碼或此檔加入Git。這個檔案的四個欄位都必須有值，`storeFile` 是絕對路徑或相對 `android/` 的路徑：

```properties
storeFile=/PRIVATE/PATH/merchant-upload.jks
storePassword=YOUR_PRIVATE_PASSWORD
keyAlias=YOUR_UPLOAD_KEY_ALIAS
keyPassword=YOUR_PRIVATE_PASSWORD
```

未提供此檔仍可編譯 **unsigned** release，不能安裝／上架；有檔但欄位不全或找不到keystore會直接失敗，不會改用debug key。確認正式API、版本號、application ID與商店資料後：

```sh
flutter build appbundle --release --dart-define=API_BASE_URL=https://YOUR_HOST/ELPSY/api/
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR_HOST/ELPSY/api/
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

驗收簽章指紋必須等於商家預期的key。正式key、Play帳號與上傳尚需商家提供；這次交付的是debug測試版。

## iOS 在 Mac 上的建置

runner最低iOS15，bundle ID `com.elpsy.elpsyShop`，採Flutter Swift Package Manager整合；Keychain entitlement已套用Debug/Profile/Release，僅本App的 `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` group，不共享其他App。refresh/device/pending使用 `first_unlock_this_device`。iOS Info.plist未開ATS明文例外。

使用macOS、相容Xcode與Flutter3.47.6，先檢查 `flutter doctor -v`、`xcodebuild -version`。Flutter生成的SPM ephemeral package由工具建立，不加入Git，也不要任意另混一套Pods配置。

```sh
flutter pub get
flutter build ios --simulator --debug --dart-define=API_BASE_URL=https://YOUR_TEST_HOST/ELPSY/api/
flutter build ios --release --no-codesign --dart-define=API_BASE_URL=https://YOUR_HOST/ELPSY/api/
open ios/Runner.xcworkspace
```

Xcode的Runner Signing & Capabilities選擇商家Apple Team，確認bundle ID、provisioning與Keychain entitlement。簽名完成後可用 `flutter run -d YOUR_IOS_DEVICE --dart-define=API_BASE_URL=https://YOUR_TEST_HOST/ELPSY/api/` 驗證真機；App Store/TestFlight需要Apple帳號與有效憑證。未簽名編譯不等於可安裝IPA。

Mac驗收需記錄：Keychain寫入後重開／背景返回、裝置首次解鎖、refresh輪替／登出、斷網與ACK遺失恢復、同bundle/team升級保留資料、iPhone/iPad布局、橫向／鍵盤與VoiceOver。卸載後Keychain可能保留，不能把卸載視為伺服器登出；同裝置登出須透過App操作。

本輪Linux只能檢查plist與Xcode設定；iOS build、Keychain執行、實體手機與商店上架仍未驗證。
