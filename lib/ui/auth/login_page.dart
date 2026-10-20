import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _passFocus.requestFocus());
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final err = await app.signIn(_user.text.trim(), _pass.text);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = err;
        _busy = false;
      });
      _pass.clear();
      _passFocus.requestFocus();
      return;
    }
    // Daily safety copy runs in the background; billing never waits for it.
    app.autoBackup();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            Expanded(
              flex: 5,
              child: Container(
                color: AppTheme.brandDark,
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.format_paint_rounded,
                          size: 32, color: Colors.white),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      AppInfo.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'GST billing, stock and accounts\nbuilt for Indian paint retailers.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 34),
                    ..._features.map(
                      (f) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(f.$1,
                                size: 17,
                                color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(width: 12),
                            Text(
                              f.$2,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Version ${AppInfo.version}  ·  Works offline  ·  Your data stays on this computer',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 4,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!wide) ...[
                        const Icon(Icons.format_paint_rounded, size: 44),
                        const SizedBox(height: 16),
                      ],
                      const Text('Sign in',
                          style: TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Enter your counter credentials to start billing.',
                        style: TextStyle(
                            fontSize: 13.5,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 26),
                      CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter):
                              _submit,
                          const SingleActivator(LogicalKeyboardKey.numpadEnter):
                              _submit,
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Field(
                              label: 'Username',
                              controller: _user,
                              prefix: const Icon(Icons.person_outline_rounded,
                                  size: 18),
                              onSubmitted: (_) => _passFocus.requestFocus(),
                            ),
                            const SizedBox(height: 14),
                            Field(
                              label: 'Password',
                              controller: _pass,
                              focusNode: _passFocus,
                              obscure: true,
                              prefix: const Icon(Icons.lock_outline_rounded,
                                  size: 18),
                              onSubmitted: (_) => _submit(),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.danger.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 17, color: AppTheme.danger),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.danger)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.login_rounded, size: 18),
                          label: Text(_busy ? 'Signing in…' : 'Sign in'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleOf(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.vpn_key_rounded, size: 15),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'First run? Use admin / admin123 and change '
                                'the password in Settings › Users.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<(IconData, String)> _features = [
    (Icons.bolt_rounded, 'Speed billing — a bill in under 10 seconds'),
    (Icons.print_rounded, 'A5 horizontal, A4 and thermal invoice printing'),
    (Icons.receipt_long_rounded, 'GSTR-1, GSTR-3B and HSN summaries'),
    (Icons.inventory_2_rounded, 'Shade, base and pack-size aware stock'),
    (Icons.account_balance_wallet_rounded, 'Customer ledgers and outstanding'),
    (Icons.backup_rounded, 'Automatic daily backups'),
  ];
}
