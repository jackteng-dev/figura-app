# Shop_app 工作規則
獨立 Flutter 顧客 App，後端 shop_bak_ap；Vue 網站 Shop_back 不搬入 App。先 fetch、讀遠端 docs/HANDOFF.md、核對 status/log/diff、ff-only。每個里程碑 format/analyze/test/build，更新交接後在功能分支 commit/push 並開 PR（main 受分支保護，CI 通過才能 merge），最後核對實際遠端，不 force。

原生 token 僅 Keychain/Keystore；禁止寫日誌、一般偏好、localStorage。App 只用 /api/mobile/customer Bearer 與公開 /api/catalog；員工 API 不引入。owner 只後端 Principal。Web harness 僅測試記憶體儲存，不是正式 Web 登入。正式 API 必須 HTTPS。

未知寫入結果保存原 UUID/body，禁止換 UUID 或自動重送版本寫入；ACK 後讀取失敗只重讀。未完成操作隔離顧客且安全儲存；新寫入先核對未完成操作。mock 金流物流不是實際服務；不宣稱真機或商店上架已完成。

work/、build/、.dart_tool/ 為忽略的工具、私有 fixture、日誌、依賴、SDK 與驗證产物；密碼、token、私有設定不可提交。只用自己全新隔離 demo DB，不改既有 DB、Flyway V1–V18 不改。iOS 真機簽名/Android 正式簽章另列交接，Linux build 不算 iOS 驗證。只改本作品，不改其他 workspace 專案。
