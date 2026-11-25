import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

// -----------------------------------------------------------------------------
// Backup input safeguard
// -----------------------------------------------------------------------------

/// Limits interactive editing before an oversized value reaches the controller.
///
/// This is a character/code-unit limit, not the final UTF-8 byte-size check.
/// Programmatic controller assignments are validated separately.
class _BackupInputFormatter extends TextInputFormatter {
  const _BackupInputFormatter(this.maxCodeUnits);

  final int maxCodeUnits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > maxCodeUnits) {
      return oldValue;
    }

    return newValue;
  }
}

// -----------------------------------------------------------------------------
// Backup page
// -----------------------------------------------------------------------------

/// Local backup and restore.
///
/// Native file operations use:
/// MethodChannel('ir.moshaver.tahsili/backup')
///
/// Expected native methods:
/// - openBackup -> String?; null means cancelled.
/// - saveBackup({content, fileName}) -> bool?; true means saved.
///
/// Security requirements outside this page:
/// - WorkspaceBackup.decode must enforce schema and resource limits.
/// - EducationStore.importBackup must validate independently.
/// - Wallet, purchase history and protected service ledger data must not
///   be imported from user-controlled backups.
/// - Import should be atomic or support reliable rollback.
/// - Native openBackup must enforce file-size limits before loading the file.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.store});

  final EducationStore store;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  static const MethodChannel _backupChannel = MethodChannel(
    'ir.moshaver.tahsili/backup',
  );

  static const int _maxBackupBytes = 5 * 1024 * 1024;

  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  bool _busy = false;

  String _operationLabel = 'لطفاً کمی صبر کن…';
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Operation lifecycle
  // ---------------------------------------------------------------------------

  bool _beginOperation(String label) {
    if (!mounted || _busy) return false;

    FocusScope.of(context).unfocus();

    setState(() {
      _busy = true;
      _error = null;
      _operationLabel = label;
    });

    return true;
  }

  void _setOperationLabel(String label) {
    if (!mounted) return;

    setState(() {
      _operationLabel = label;
    });
  }

  void _endOperation() {
    if (!mounted) return;

    setState(() {
      _busy = false;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;

    showMessage(context, message);
  }

  void _setError(String message) {
    if (!mounted) return;

    setState(() {
      _error = message;
    });
  }

  void _handleError(Object error, {required String fallback}) {
    if (error is BackupFormatException) {
      _setError(error.toString());
      return;
    }

    if (error is MissingPluginException) {
      _setError(
        'انتخاب یا ذخیره فایل در این نسخه یا پلتفرم '
        'پیاده‌سازی نشده است. '
        'می‌توانی از روش کپی و چسباندن متن استفاده کنی.',
      );
      return;
    }

    if (error is PlatformException) {
      final message = error.message?.trim() ?? '';

      _setError(message.isEmpty ? fallback : message);
      return;
    }

    final message = friendlyError(error).trim();

    _setError(message.isEmpty ? fallback : message);
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String _validateBackupSize(String raw) {
    // Check code-unit size before trim or UTF-8 allocation.
    if (raw.length > _maxBackupBytes) {
      throw const BackupFormatException(
        'حجم فایل پشتیبان بیشتر از حد مجاز ۵ مگابایت است.',
      );
    }

    if (raw.trim().isEmpty) {
      throw const BackupFormatException('محتوای پشتیبان خالی است.');
    }

    final byteLength = utf8.encode(raw).length;

    if (byteLength > _maxBackupBytes) {
      throw const BackupFormatException(
        'حجم فایل پشتیبان بیشتر از حد مجاز ۵ مگابایت است.',
      );
    }

    return raw;
  }

  String _validateBackup(String raw) {
    final validated = _validateBackupSize(raw);

    // This call must reject unsupported versions, invalid sections,
    // oversized collections and excessive nesting where applicable.
    WorkspaceBackup.decode(validated);

    return validated;
  }

  Future<String> _exportValidatedBackup() async {
    final raw = await widget.store.exportBackup();

    return _validateBackup(raw);
  }

  // ---------------------------------------------------------------------------
  // Dialogs
  // ---------------------------------------------------------------------------

  Future<bool> _confirmCopy() async {
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('کپی اطلاعات خصوصی؟'),
            content: const Text(
              'متن پشتیبان رمزگذاری نشده است و ممکن است شامل '
              'پروفایل، گفت‌وگوها و اطلاعات تحصیلی خصوصی باشد.\n\n'
              'حافظه موقت، بسته به تنظیمات دستگاه، ممکن است '
              'در اختیار برنامه‌های دیگر قرار بگیرد یا با '
              'دستگاه‌های دیگر همگام شود.\n\n'
              'اگر امکانش را داری، ذخیره فایل در یک محل امن '
              'را ترجیح بده.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('کپی پشتیبان'),
              ),
            ],
          ),
        );
      },
    );

    return confirmed == true;
  }

  Future<bool> _confirmRestore() async {
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('بازیابی پشتیبان؟'),
            content: const Text(
              'اطلاعات تحصیلی فعلی با محتوای پشتیبان '
              'جایگزین می‌شود.\n\n'
              'کیف پرهای سیمرغ و سابقه خرید نباید از '
              'پشتیبان بازیابی شوند.\n\n'
              'فقط پشتیبانی را بازیابی کن که خودت تهیه '
              'کرده‌ای یا به منبع آن اعتماد داری.\n\n'
              'پیش از ادامه، بهتر است از اطلاعات فعلی '
              'یک نسخه پشتیبان تهیه کنی.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('جایگزینی و بازیابی'),
              ),
            ],
          ),
        );
      },
    );

    return confirmed == true;
  }

  // ---------------------------------------------------------------------------
  // Native file import
  // ---------------------------------------------------------------------------

  Future<void> _openBackupFile() async {
    if (!_beginOperation('در حال انتخاب و بررسی فایل…')) {
      return;
    }

    try {
      final raw = await _backupChannel.invokeMethod<String>('openBackup');

      if (!mounted || raw == null) return;

      final validated = _validateBackup(raw);

      _input.text = validated;

      _showMessage(
        'فایل خوانده شد و بررسی ساختار انجام شد. '
        'برای جایگزینی اطلاعات، دکمه بازیابی را بزن.',
      );
    } on Object catch (error) {
      _handleError(error, fallback: 'خواندن فایل پشتیبان انجام نشد.');
    } finally {
      _endOperation();
    }
  }

  // ---------------------------------------------------------------------------
  // Native file export
  // ---------------------------------------------------------------------------

  Future<void> _saveBackupFile() async {
    if (!_beginOperation('در حال آماده‌سازی فایل پشتیبان…')) {
      return;
    }

    try {
      final raw = await _exportValidatedBackup();

      if (!mounted) return;

      _setOperationLabel('محل ذخیره فایل را انتخاب کن…');

      final now = DateTime.now();

      final year = now.year.toString().padLeft(4, '0');
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');
      final hour = now.hour.toString().padLeft(2, '0');
      final minute = now.minute.toString().padLeft(2, '0');
      final second = now.second.toString().padLeft(2, '0');

      final saved = await _backupChannel
          .invokeMethod<bool>('saveBackup', <String, Object>{
            'content': raw,
            'fileName':
                'simorgh-backup-$year-$month-$day-$hour$minute$second.json',
          });

      if (!mounted) return;

      if (saved == true) {
        _showMessage('فایل پشتیبان ذخیره شد.');
      } else {
        _showMessage('ذخیره فایل انجام نشد یا لغو شد.');
      }
    } on Object catch (error) {
      _handleError(error, fallback: 'ذخیره فایل پشتیبان انجام نشد.');
    } finally {
      _endOperation();
    }
  }

  // ---------------------------------------------------------------------------
  // Clipboard export
  // ---------------------------------------------------------------------------

  Future<void> _copyBackup() async {
    if (!_beginOperation('در انتظار تأیید کپی پشتیبان…')) {
      return;
    }

    try {
      final confirmed = await _confirmCopy();

      if (!mounted || !confirmed) return;

      _setOperationLabel('در حال آماده‌سازی و کپی پشتیبان…');

      final raw = await _exportValidatedBackup();

      if (!mounted) return;

      await Clipboard.setData(ClipboardData(text: raw));

      _showMessage(
        'متن پشتیبان کپی شد. پس از انتقال به محل امن، '
        'آن را در حافظه موقت باقی نگذار.',
      );
    } on Object catch (error) {
      _handleError(error, fallback: 'کپی متن پشتیبان انجام نشد.');
    } finally {
      _endOperation();
    }
  }

  // ---------------------------------------------------------------------------
  // Clipboard import
  // ---------------------------------------------------------------------------

  Future<void> _pasteBackup() async {
    if (!_beginOperation('در حال خواندن و بررسی متن…')) {
      return;
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);

      if (!mounted) return;

      final raw = data?.text;

      if (raw == null || raw.isEmpty) {
        _showMessage('متنی در حافظه موقت وجود ندارد.');
        return;
      }

      // Do not replace the current editor with invalid clipboard data.
      final validated = _validateBackup(raw);

      _input.text = validated;

      _showMessage(
        'متن وارد شد و بررسی ساختار انجام شد. '
        'هنوز هیچ اطلاعاتی بازیابی نشده است.',
      );
    } on Object catch (error) {
      _handleError(error, fallback: 'خواندن متن پشتیبان انجام نشد.');
    } finally {
      _endOperation();
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  Future<void> _restore() async {
    // Lock before validation and before showing the confirmation dialog.
    // This prevents multiple restore dialogs and overlapping operations.
    if (!_beginOperation('در حال بررسی پشتیبان…')) {
      return;
    }

    try {
      // Capture exactly the text validated and confirmed for this operation.
      // Do not trim before the size check.
      final raw = _validateBackup(_input.text);

      _setOperationLabel('در انتظار تأیید بازیابی…');

      final confirmed = await _confirmRestore();

      if (!mounted || !confirmed) return;

      _setOperationLabel('در حال بازیابی اطلاعات…');

      // Must validate independently and preserve protected wallet/purchase
      // data. UI validation is not a security boundary.
      //
      // Import should be atomic, or roll back on failure.
      final sections = await widget.store.importBackup(raw);

      if (!mounted) return;

      _input.clear();

      _showMessage(
        'بازیابی انجام شد؛ '
        '${faNumber(sections)} بخش بازیابی شد.',
      );
    } on Object catch (error) {
      _handleError(error, fallback: 'بازیابی پشتیبان انجام نشد.');
    } finally {
      _endOperation();
    }
  }

  void _clearInput() {
    if (_busy) return;

    _input.clear();

    setState(() {
      _error = null;
    });
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  Widget _actionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool filled = false,
  }) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );

    if (filled) {
      return FilledButton(onPressed: _busy ? null : onPressed, child: content);
    }

    return OutlinedButton(onPressed: _busy ? null : onPressed, child: content);
  }

  Widget _buildEditor() {
    return TextField(
      controller: _input,
      focusNode: _inputFocus,
      enabled: !_busy,
      minLines: 4,
      maxLines: 8,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      inputFormatters: const [_BackupInputFormatter(_maxBackupBytes)],
      decoration: const InputDecoration(
        labelText: 'متن پشتیبان',
        hintText: '{"version": ...}',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
        helperText: 'حداکثر حجم: ۵ مگابایت با کدگذاری UTF-8',
        helperMaxLines: 2,
      ),
    );
  }

  Widget _buildRestoreActions() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _input,
      builder: (context, value, _) {
        // Avoid scanning a potentially large document during every build.
        final hasText = value.text.isNotEmpty;

        return LayoutBuilder(
          builder: (context, constraints) {
            final actions = <Widget>[
              _actionButton(
                onPressed: _pasteBackup,
                icon: Icons.content_paste,
                label: 'چسباندن و بررسی',
              ),
              FilledButton.icon(
                onPressed: _busy || !hasText ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('بازیابی اطلاعات'),
                ),
              ),
            ];

            if (constraints.maxWidth < 360) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [actions[0], const SizedBox(height: 8), actions[1]],
              );
            }

            return Row(
              children: [
                Expanded(child: actions[0]),
                const SizedBox(width: 8),
                Expanded(child: actions[1]),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBusyOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Theme.of(context).colorScheme.scrim.withOpacity(0.18),
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: _operationLabel,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        _operationLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(height: 1.8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        // Prevent normal back navigation while an operation is in progress.
        // This does not protect against process termination.
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('پشتیبان‌گیری و بازیابی'),
            automaticallyImplyLeading: !_busy,
          ),
          body: SafeArea(
            top: false,
            child: Stack(
              children: [
                AbsorbPointer(
                  absorbing: _busy,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      const NoticeCard(
                        text:
                            'پشتیبان برای انتقال و نگهداری '
                            'اطلاعات تحصیلی مانند پروفایل، '
                            'برنامه‌ها، امتحان‌ها، فلش‌کارت‌ها، '
                            'گفت‌وگوها، جلسه‌های تدریس، یادآورها '
                            'و گزارش‌های مشاوره است. '
                            'بخش‌های دقیق به نسخه پشتیبان و '
                            'پیاده‌سازی ذخیره‌سازی بستگی دارند. '
                            'کیف پرهای سیمرغ و سابقه خرید '
                            'نباید در پشتیبان قابل بازیابی باشند.',
                        icon: Icons.backup_outlined,
                      ),
                      const SizedBox(height: 8),
                      const NoticeCard(
                        text:
                            'این فایل متن ساده است، '
                            'رمزگذاری نشده و ممکن است شامل '
                            'اطلاعات خصوصی باشد. آن را در '
                            'محل امن نگه دار و با افراد '
                            'غیرمجاز به اشتراک نگذار. '
                            'همگام‌سازی ابری محل ذخیره یا '
                            'حافظه موقت به تنظیمات دستگاه '
                            'و سرویس انتخاب‌شده بستگی دارد.',
                        warning: true,
                        icon: Icons.privacy_tip_outlined,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: NoticeCard(text: _error!, warning: true),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
                        'تهیه نسخه پشتیبان',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _actionButton(
                        onPressed: _saveBackupFile,
                        icon: Icons.save_alt_outlined,
                        label: 'ذخیره فایل پشتیبان',
                        filled: true,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : _copyBackup,
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('کپی متن پشتیبان؛ روش جایگزین'),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'بازیابی',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _actionButton(
                        onPressed: _openBackupFile,
                        icon: Icons.folder_open_outlined,
                        label: 'انتخاب و بررسی فایل پشتیبان',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'انتخاب فایل یا چسباندن متن، '
                        'اطلاعات فعلی را تغییر نمی‌دهد. '
                        'جایگزینی فقط پس از تأیید بازیابی '
                        'انجام می‌شود.',
                        style: TextStyle(height: 1.8),
                      ),
                      const SizedBox(height: 12),
                      _buildEditor(),
                      const SizedBox(height: 10),
                      _buildRestoreActions(),
                      const SizedBox(height: 6),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _input,
                        builder: (context, value, _) {
                          return Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              onPressed: _busy || value.text.isEmpty
                                  ? null
                                  : _clearInput,
                              icon: const Icon(Icons.clear),
                              label: const Text('پاک‌کردن متن واردشده'),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const NoticeCard(
                        text:
                            'بازیابی اطلاعات فعلی را '
                            'جایگزین می‌کند. ابتدا یک نسخه '
                            'پشتیبان از وضعیت فعلی تهیه کن. '
                            'بررسی معتبر بودن ساختار فایل، '
                            'به‌تنهایی اصالت یا قابل اعتماد '
                            'بودن محتوای آن را اثبات نمی‌کند.',
                        warning: true,
                        icon: Icons.warning_amber_outlined,
                      ),
                    ],
                  ),
                ),
                if (_busy) _buildBusyOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
