import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import 'common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool registering = false, busy = false;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final api = ref.read(apiProvider);
      if (registering) {
        await api.register(
          username.text.trim(),
          password.text,
          name.text.trim(),
        );
        if (mounted) setState(() => registering = false);
      }
      await api.login(username.text.trim(), password.text);
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
            field(
              username,
              '帳號',
              validator: (v) =>
                  RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(v?.trim() ?? '')
                  ? null
                  : '帳號需為 3–32 個英數或底線',
            ),
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
            if (registering)
              field(
                name,
                '顯示名稱',
                validator: (v) =>
                    v == null || v.trim().isEmpty || v.trim().length > 80
                    ? '請填寫 1–80 字的名稱'
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

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RequestView(
    load: () => ref.read(apiProvider).request('GET', 'me'),
    render: (data, reload) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          infoCard('我的帳戶', [
            Text('${data['displayName']}'),
            Text('@${data['username']}'),
          ]),
          field(name, '新的顯示名稱'),
          WriteButton(
            label: '更新名稱',
            action: () async {
              if (name.text.trim().isEmpty || name.text.trim().length > 80) {
                return;
              }
              await ref.read(writesProvider).run('PATCH', 'me', {
                'displayName': name.text.trim(),
              });
              reload();
            },
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
