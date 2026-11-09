# 裝置／正式環境待驗

Linux可驗證 Dart客戶端、Flutter widget、瀏覽器測試harness、Android APK與原生模擬器；本輪實際結果見HANDOFF與verification JSON。Android測試APK／USB安裝、原生驗收重跑與iOS建置步驟見 [DEVICE_ACCEPTANCE](DEVICE_ACCEPTANCE.md)。沒有 Android/iOS 實體手機、iOS/macOS toolchain 或商店憑證。

1. Android 真機安裝 debug APK，使用實際可達 HTTPS 後端，驗證 Keystore 儲存、關閉再開／背景恢復、慢網／斷網／未知結果／401輪替／登出、新版本升級與資料清除。Android emulator 10.0.2.2 不等於手機能連到使用者電腦。
2. macOS Xcode/CocoaPods build／模擬器／真機；核對 deployment target、Keychain 存取與裝置鎖定、背景返回、iPad／橫向／鍵盤與可及性。現有 iOS runner 不等於 iOS build 通過，不放寬 ATS 或使用 HTTP。
3. 商家正式 bundle/application IDs、品牌素材／App icon、Android 自有 keystore／安全備份、Apple team／provisioning、版本號與商店測試渠道、隱私揭露。已支援私人key.properties與iOS Keychain entitlement，仍需商家憑證與真實簽名验收；unsigned release compile 不可直接安裝上架。
4. 部署網域與 TLS/可達性；正式金流、物流／通知與推播、會員限流／重設等沿用後端待驗計畫。mock 不代表真正營業。

上述裝置與正式營運驗收是下一階段，不把訂金尾款／延期等選擇性商家擴充加成已完成整筆預購 MVP 的必要條件。
