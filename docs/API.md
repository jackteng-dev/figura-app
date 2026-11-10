# API與安全

Base URI 必須 HTTPS 且以 /figura/api/ 結尾；debug 限 loopback/10.0.2.2 HTTP。登入 `/mobile/customer/auth` 與受保護 `/mobile/customer/*` 使用 JSON/Bearer，公開 `/catalog` 不帶token；完全不讀寫網站Cookie／CSRF、員工API或私有S3。圖片只用已知public route重建URL，不接受任意外部圖URL或夾帶token。

access 只記憶體，refresh與deviceUUID使用原生secure storage；密碼不保存。refresh只有同時一筆，伺服器先拒絕401才重試一次原請求；網路或5xx不自動重送。登出本機清除並呼叫遠端撤銷，回應未知顯示撤銷未確認；登出與refresh競爭不讓遲到pair恢復登入。暫時503保留refresh讓人重試，明確401失效才清除。網站Token/staffToken不被新後端接受。

寫入先安全保存PendingWrite owner／method／path／完整body。下單／預購取消／付款意圖／模擬結果都有原UUID，未知結果凍結其他寫入，只可明確重試原命令；即使process重啟仍可核對。版本寫入（cart、address、profile、現貨取消）先GET当前資料再由人確認，不盲重送。ACK立即清pending，後續GET失敗只讀取；操作紀錄按已登入owner隔離，登出後不顯示別人pending，但原owner再登入仍可核對。pending收件資料由原生secure storage加密保存，保留至核對完成，正式保存期限／隱私政策需商家確認。

金額只展示後端報價與order snapshot，expectedSubtotal作server核對，不能當真實信任價格；cart/address/order版本衝突拒絕，自行重讀後再操作。App只操作本人訂單，不包含員工到貨／分配／出貨功能。預購獨立resource/quota與現貨cart／庫存分開。

原生 API exact route合約見 [後端文件](https://github.com/jackteng-dev/shop_bak_ap/blob/main/docs/MOBILE_API.md)。mock enabled/canStart 由伺服器決定。沒有實際支付SDK、推播或外部深連結，沒有日誌token/password、localStorage、付費或外部訊息。
