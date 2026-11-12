# Shop_app 工作規則

## 部署限制（最優先，2026-11-12）

本 repo 的 main 會由作者的自架伺服器自動部署（GitHub Actions 發布映像 → 伺服器 CD 自然輪詢、先備份與隔離演練再切換）。在本機或任何 AI 工具修改時，**下列規則優先於本檔其他內容**：

1. **一律走 PR**：開功能分支、push、開 PR，`verify` CI 通過後才 merge。不可直接 push main、不可 force push（分支保護也會拒絕）。本檔較舊段落提到「push main」者，以本規則為準。
2. **本機開發用本機資料庫**：用 repo 內的 docker compose／說明啟動全新空資料庫，不要連線或下載正式資料庫，不要把帳密、token、`.env` 寫進 Git。
3. **受保護路徑（CD 資料契約）**：PR 若修改下列路徑，CD 會拒絕自動部署。請先停下，告知作者在伺服器端執行受控切換（contract switch）後才能 merge：
   - （本 repo 無伺服器 CD 受保護路徑）
4. 只在本機跑測試、編譯、啟動，不會修改上述檔案（Maven 會把 resources 複製到 `target/`，該目錄已被忽略）。
5. 本 repo 沒有自動 CD；APK 由 `android-sandbox-apk.yml` 手動 workflow 建置發布（`sandbox-latest`）。API 位址為 `/figura/api/`。

push 前請用 `git diff --stat origin/main` 確認是否動到受保護路徑，並在 PR 說明中註明。

獨立 Flutter 顧客 App，後端 shop_bak_ap；Vue 網站 Shop_back 不搬入 App。先 fetch、讀遠端 docs/HANDOFF.md、核對 status/log/diff、ff-only。每個里程碑 format/analyze/test/build，更新交接後在功能分支 commit/push 並開 PR（main 受分支保護，CI 通過才能 merge），最後核對實際遠端，不 force。

原生 token 僅 Keychain/Keystore；禁止寫日誌、一般偏好、localStorage。App 只用 /api/mobile/customer Bearer 與公開 /api/catalog；員工 API 不引入。owner 只後端 Principal。Web harness 僅測試記憶體儲存，不是正式 Web 登入。正式 API 必須 HTTPS。

未知寫入結果保存原 UUID/body，禁止換 UUID 或自動重送版本寫入；ACK 後讀取失敗只重讀。未完成操作隔離顧客且安全儲存；新寫入先核對未完成操作。mock 金流物流不是實際服務；不宣稱真機或商店上架已完成。

work/、build/、.dart_tool/ 為忽略的工具、私有 fixture、日誌、依賴、SDK 與驗證产物；密碼、token、私有設定不可提交。只用自己全新隔離 demo DB，不改既有 DB、Flyway V1–V18 不改。iOS 真機簽名/Android 正式簽章另列交接，Linux build 不算 iOS 驗證。只改本作品，不改其他 workspace 專案。
