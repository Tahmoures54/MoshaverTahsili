import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

const simorghBazaarUrl =
    'https://cafebazaar.ir/app/ir.moshaver.tahsili';

const simorghReferralMessage =
    'من از برنامه «سیمرغ؛ مشاور هوشمند تحصیلی» '
    'برای برنامه‌ریزی و مسیر یادگیری استفاده می‌کنم. '
    'اگر دوست داری تو هم امتحانش کنی، از این لینک نصبش کن:\n'
    '$simorghBazaarUrl';

enum _ReferralOperation {
  share,
  copyMessage,
  copyLink,
}

/// Shares only the public referral message through the existing native channel.
///
/// No contact access, referral identifier or additional user data is requested
/// by this page.
///
/// Native channel contract:
/// - Channel: ir.moshaver.tahsili/share
/// - Method: shareText
/// - Arguments: {'text': String}
/// - Result:
///   - true: native handler accepted the request
///   - false: native handler reported that it could not handle the request
///   - null: accepted for compatibility with existing void-returning handlers
///
/// Acceptance does not prove the user actually sent the message.
class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});

  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  static const MethodChannel _shareChannel =
      MethodChannel('ir.moshaver.tahsili/share');

  _ReferralOperation? _operation;

  bool get _isBusy => _operation != null;

  void _notify(String message) {
    if (!mounted) return;
    showMessage(context, message);
  }

  /// Prevents overlapping share/copy requests and safely clears loading state.
  Future<void> _runOperation(
    _ReferralOperation operation,
    Future<void> Function() action, {
    required String fallbackMessage,
  }) async {
    if (!mounted || _isBusy) return;

    setState(() {
      _operation = operation;
    });

    try {
      await action();
    } catch (_) {
      // Do not expose platform error details to the user.
      _notify(fallbackMessage);
    } finally {
      if (mounted) {
        setState(() {
          _operation = null;
        });
      }
    }
  }

  Future<void> _share() {
    return _runOperation(
      _ReferralOperation.share,
      () async {
        try {
          final result = await _shareChannel.invokeMethod<bool>(
            'shareText',
            const <String, Object>{
              'text': simorghReferralMessage,
            },
          );

          if (result == false) {
            _notify(
              'اشتراک‌گذاری انجام نشد. '
              'می‌توانی متن معرفی یا لینک نصب را کپی کنی.',
            );
          }

          // Do not show "sent successfully":
          // opening a share sheet does not confirm delivery.
          //
          // A null result remains valid for native handlers that return void.
        } on MissingPluginException {
          _notify(
            'اشتراک‌گذاری در این نسخه یا دستگاه در دسترس نیست. '
            'متن معرفی یا لینک نصب را کپی کن.',
          );
        } on PlatformException {
          _notify(
            'باز کردن پنجره اشتراک‌گذاری ممکن نشد. '
            'متن معرفی یا لینک نصب را کپی کن.',
          );
        }
      },
      fallbackMessage:
          'اشتراک‌گذاری ممکن نشد. لطفاً از گزینه کپی استفاده کن.',
    );
  }

  Future<void> _copyMessage() {
    return _copy(
      operation: _ReferralOperation.copyMessage,
      text: simorghReferralMessage,
      successMessage: 'متن معرفی و لینک نصب کپی شد.',
    );
  }

  Future<void> _copyLink() {
    return _copy(
      operation: _ReferralOperation.copyLink,
      text: simorghBazaarUrl,
      successMessage: 'لینک نصب کپی شد.',
    );
  }

  Future<void> _copy({
    required _ReferralOperation operation,
    required String text,
    required String successMessage,
  }) {
    return _runOperation(
      operation,
      () async {
        try {
          await Clipboard.setData(
            ClipboardData(text: text),
          );

          _notify(successMessage);
        } on MissingPluginException {
          _notify(
            'کپی خودکار در این محیط در دسترس نیست. '
            'متن یا لینک را از بخش بالا انتخاب و کپی کن.',
          );
        } on PlatformException {
          _notify(
            'کپی در کلیپ‌بورد ممکن نشد. '
            'متن یا لینک را از بخش بالا انتخاب و کپی کن.',
          );
        }
      },
      fallbackMessage:
          'کپی انجام نشد. متن یا لینک را دستی انتخاب و کپی کن.',
    );
  }

  Widget _operationIcon(
    _ReferralOperation operation,
    IconData icon,
  ) {
    if (_operation != operation) {
      return Icon(icon);
    }

    return const SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildIntroduction(ThemeData theme) {
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(
          child: ExcludeSemantics(
            child: SimorghMark(size: 112),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'یادگیری با همراهی دوستان شیرین‌تر است!',
          textAlign: TextAlign.center,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'سیمرغ را به هم‌کلاسی‌ها و دوستانت معرفی کن '
          'تا آن‌ها هم با ابزارهای برنامه‌ریزی، مرور '
          'و راهنمایی تحصیلی آشنا شوند.',
          textAlign: TextAlign.center,
          style: textTheme.bodyLarge?.copyWith(
            height: 1.9,
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageCard(ThemeData theme) {
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'متن آماده معرفی',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              simorghReferralMessage,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.start,
              style: textTheme.bodyLarge?.copyWith(
                height: 1.9,
              ),
            ),
            const Divider(height: 32),
            Semantics(
              header: true,
              child: Text(
                'لینک نصب از کافه‌بازار',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Explicit LTR keeps the URL readable within the RTL page.
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                simorghBazaarUrl,
                textAlign: TextAlign.left,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                  height: 1.7,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _isBusy ? null : _copyLink,
                icon: _operationIcon(
                  _ReferralOperation.copyLink,
                  Icons.link_outlined,
                ),
                label: Text(
                  _operation == _ReferralOperation.copyLink
                      ? 'در حال کپی لینک…'
                      : 'کپی فقط لینک نصب',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _isBusy ? null : _share,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
          icon: _operationIcon(
            _ReferralOperation.share,
            Icons.share_outlined,
          ),
          label: Text(
            _operation == _ReferralOperation.share
                ? 'در حال باز کردن اشتراک‌گذاری…'
                : 'معرفی به دوستان',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isBusy ? null : _copyMessage,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
          icon: _operationIcon(
            _ReferralOperation.copyMessage,
            Icons.copy_outlined,
          ),
          label: Text(
            _operation == _ReferralOperation.copyMessage
                ? 'در حال کپی متن…'
                : 'کپی متن معرفی و لینک',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildPrivacyNotice(ThemeData theme) {
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'چه چیزی به اشتراک گذاشته می‌شود؟',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'این صفحه فقط متن معرفی بالا و لینک عمومی نصب '
                    'را برای اشتراک‌گذاری به سیستم دستگاه می‌فرستد؛ '
                    'شماره تماس، اطلاعات حساب یا سوابق تحصیلی تو '
                    'به این متن اضافه نمی‌شود. '
                    'انتخاب برنامه و گیرنده با خودت است و نحوه پردازش '
                    'پیام در برنامه مقصد تابع سیاست‌های همان برنامه است.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.9,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('معرفی سیمرغ به دوستان'),
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 680,
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  24,
                ),
                children: [
                  _buildIntroduction(theme),
                  const SizedBox(height: 24),
                  _buildMessageCard(theme),
                  const SizedBox(height: 18),
                  _buildActions(),
                  const SizedBox(height: 18),
                  _buildPrivacyNotice(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
