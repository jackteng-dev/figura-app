import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/identity.dart';
import '../core/providers.dart';
import 'common.dart';
import 'engagement.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final form = GlobalKey<FormState>();
  // 登入：identifier 為手機或 Email。註冊：phone＋email＋password（不再有帳號名稱與暱稱）。
  final identifier = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool registering = false, busy = false;
  @override
  void dispose() {
    identifier.dispose();
    phone.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final api = ref.read(apiProvider);
      String loginId;
      if (registering) {
        final mail = normalizeEmail(email.text)!;
        await api.register(
          email: mail,
          phone: normalizePhone(phone.text)!,
          password: password.text,
        );
        if (mounted) {
          setState(() => registering = false);
          identifier.text = mail;
        }
        loginId = mail;
      } else {
        loginId = normalizeLoginId(identifier.text)!;
      }
      try {
        await api.login(loginId, password.text);
      } on ShopError catch (e) {
        // 不透露帳號是否存在
        if (e.status == 401) throw ShopError('手機／Email 或密碼不正確', status: 401);
        rethrow;
      }
      password.clear();
      await ref.read(writesProvider).restore();
      if (mounted) context.go('/products');
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      password.clear();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 24),
      const Text(
        '收藏，從這裡開始。',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      Text(registering ? '建立 Figura 會員' : '登入後管理收藏與訂單'),
      const SizedBox(height: 32),
      Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!registering)
              field(
                identifier,
                '手機或 Email',
                keyboard: TextInputType.emailAddress,
                validator: (v) => normalizeLoginId(v) == null
                    ? '請輸入 09 開頭的手機號碼或有效的 Email'
                    : null,
              ),
            if (registering) ...[
              field(
                phone,
                '手機號碼',
                keyboard: TextInputType.phone,
                validator: (v) =>
                    normalizePhone(v) == null ? '請輸入 09 開頭的 10 碼手機' : null,
              ),
              field(
                email,
                'Email',
                keyboard: TextInputType.emailAddress,
                validator: (v) =>
                    normalizeEmail(v) == null ? 'Email 格式不正確' : null,
              ),
            ],
            field(
              password,
              '密碼',
              secret: true,
              validator: (v) => v == null || v.isEmpty
                  ? '請填寫密碼'
                  : utf8.encode(v).length > 72
                  ? '密碼不可超過 72 bytes'
                  : registering && v.length < 12
                  ? '密碼至少 12 字元'
                  : null,
            ),
            FilledButton(
              onPressed: busy ? null : submit,
              child: Text(
                busy
                    ? '處理中…'
                    : registering
                    ? '註冊並登入'
                    : '登入',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() => registering = !registering),
              child: Text(registering ? '已有帳號，登入' : '建立新帳號'),
            ),
          ],
        ),
      ),
    ],
  );
}

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => RequestView(
    load: () => ref.read(apiProvider).request('GET', 'me'),
    render: (data, reload) {
      final mail = data['email'] as String?, mobile = data['phone'] as String?;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          infoCard('會員資料', [
            Text('Email：${mail ?? '未設定'}'),
            if (mail != null)
              // Email 驗證信目前為測試環境模擬、不會真的寄出：只顯示狀態，不要求去收信
              Text(data['emailVerified'] == true ? 'Email 已驗證' : 'Email 尚未驗證'),
            Text('手機：${mobile ?? '未設定'}'),
          ]),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.push('/account/favorites'),
            child: const Text('我的收藏'),
          ),
          OutlinedButton(
            onPressed: () => context.push('/account/notification-preferences'),
            child: const Text('通知設定'),
          ),
          const NotificationsEntry(),
          OutlinedButton(
            onPressed: () => context.push('/account/shipments'),
            child: const Text('我的出貨'),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.push('/addresses'),
            child: const Text('收件地址'),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: ref.watch(writesProvider).busy
                ? null
                : () async {
                    try {
                      await ref.read(apiProvider).logout();
                    } catch (e) {
                      if (context.mounted) message(context, e);
                    }
                    await ref.read(writesProvider).restore();
                    if (context.mounted) context.go('/login');
                  },
            child: const Text('登出此裝置'),
          ),
          const SizedBox(height: 24),
          const Text('目前付款與配送為模擬流程，尚未接入正式服務。'),
        ],
      );
    },
  );
}
