
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

/// Local backup and restore.
///
/// Backup is handled locally through the platform file picker or clipboard.
/// The AI wallet and purchase history must never be restored from a backup.
class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    required this.store,
  });

  final EducationStore store;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  static const MethodChannel backupChannel =
      MethodChannel('ir.moshaver.tahsili/backup');

  /// Maximum accepted backup size.
  ///
  /// This is a UI-level safeguard. The same or stricter limit must also
  /// be enforced inside WorkspaceBackup.decode and EducationStore.importBackup.
  static const int _maxBackupBytes = 5 * 1024 * 1024;

  final TextEditingController input = TextEditingController();

  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  bool _beginOperation() {
    if (!mounted || busy) return false;

    setState(() => busy = true);
    return true;
  }

  void _endOperation() {
    if (mounted) {
      setState(() => busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showMessage(context, message);
  }

  String _validateBackupSize(String raw) {
    if (raw.trim().isEmpty) {
      throw const BackupFormatException(
        'محتوای فایل پشتیبان خالی است.',
      );
    }

    // Avoid allocating a large UTF-8 buffer for obviously oversized input.
    if (raw.length > _maxBackupBytes) {
      throw const BackupFormatException(
        'حجم فایل پشتیبان بیشتر از حد مجاز است.',
      );
    }

    final byteLength = utf8.encode(raw).length;

    if (byteLength > _maxBackupBytes) {
      throw const BackupFormatException(
        'حجم فایل پشتیبان بیشتر از حد مجاز است.',
      );
    }

    return raw;
  }

  /// Reads and validates a backup before it is placed in the editor.
  Future<void> openBackupFile() async {
    if (!_beginOperation()) return;

    try {
      final raw = await backupChannel.invokeMethod<String>('openBackup');

      if (!mounted || raw == null) return;

      final validatedRaw = _validateBackupSize(raw);

      // Validate the structure before asking the user to restore it.
      WorkspaceBackup.decode(validatedRaw);

      input.text = validatedRaw;

      _showMessage(
        'فایل پشتیبان خوانده شد؛ برای تأیید و بازیابی اقدام کن.',
      );
    } on BackupFormatException catch (error) {
      _showMessage(error.toString());
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'خواندن فایل انجام نشد.');
    } on Object catch (error) {
      _showMessage(friendlyError(error));
    } finally {
      _endOperation();
    }
  }

  /// Exports the current local data and saves it through the native channel.
  Future<void> saveBackupFile() async {
    if (!_beginOperation()) return;

    try {
      final raw = await widget.store.exportBackup();

      _validateBackupSize(raw);

      // Validate the exported content too. This helps detect unexpected
      // serialization problems before saving the file.
      WorkspaceBackup.decode(raw);

      final date = DateTime.now().toIso8601String().substring(0, 10);

      final saved = await backupChannel.invokeMethod<bool>(
        'saveBackup',
        {
          'content': raw,
          'fileName': 'simorgh-backup-$date.json',
        },
      );

      if (!mounted) return;

      if (saved == true) {
        _showMessage('فایل پشتیبان ذخیره شد.');
      }
    } on BackupFormatException catch (error) {
      _showMessage(error.toString());
    } on PlatformException catch (error) {
      _showMessage(error.message ?? 'ذخیره فایل انجام نشد.');
    } on Object catch (error) {
      _showMessage(friendlyError(error));
    } finally {
      _endOperation();
    }
  }

  /// Copies the current backup to the system clipboard.
  Future<void> copyBackup() async {
    if (!_beginOperation()) return;

    try {
      final raw = await widget.store.exportBackup();

      _validateBackupSize(raw);
      WorkspaceBackup.decode(raw);

      await Clipboard.setData(
        ClipboardData(text: raw),
      );

      _showMessage('متن پشتیبان کپی شد.');
    } on BackupFormatException catch (error) {
      _showMessage(error.toString());
    } on Object catch (error) {
      _showMessage(friendlyError(error));
    } finally {
      _endOperation();
    }
  }

  /// Reads backup text from the clipboard.
  Future<void> paste() async {
    if (!_beginOperation()) return;

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);

      if (!mounted) return;

      final raw = data?.text ?? '';

      if (raw.isEmpty) {
        _showMessage('متنی در حافظه موقت وجود ندارد.');
        return;
      }

      _validateBackupSize(raw);

      input.text = raw;

      _showMessage('متن پشتیبان وارد شد؛ ساختار آن هنگام بازیابی بررسی می‌شود.');
    } on BackupFormatException catch (error) {
      _showMessage(error.toString());
    } on Object catch (error) {
      _showMessage(friendlyError(error));
    } finally {
      _endOperation();
    }
  }

  Future<bool> _confirmRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('بازیابی پشتیبان؟'),
        content: const Text(
          'اطلاعات تحصیلی فعلی این گوشی با محتوای پشتیبان جایگزین می‌شود.\n\n'
          'کیف پرهای سیمرغ و سابقه خرید تغییر نمی‌کنند.\n\n'
          'پیشنهاد می‌شود پیش از بازیابی، از اطلاعات فعلی نیز یک نسخه پشتیبان تهیه کنی.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('بازیابی'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  /// Validates, confirms and restores the selected backup.
  Future<void> restore() async {
    if (busy) return;

    final raw = input.text.trim();

    // Validate before showing the destructive confirmation dialog.
    try {
      _validateBackupSize(raw);
      WorkspaceBackup.decode(raw);
    } on BackupFormatException catch (error) {
      _showMessage(error.toString());
      return;
    } on Object catch (error) {
      _showMessage(friendlyError(error));
      return;
    }

    final confirmed = await _confirmRestore();

    if (!mounted || confirmed != true) return;

    if (!_beginOperation()) return;

    try {
      // importBackup must perform its own complete validation.
      // UI validation alone is not a security boundary.
      final sections = await widget.store.importBackup(raw);

      if (!mounted) return;

      input.clear();

      _showMessage(
        'بازیابی انجام شد؛ ${faNumber(sections)} بخش بازیابی شد.',
      );
    } on BackupFormatException catch (error) {
      _showMessage(error.toString());
    } on Object catch (error) {
      _showMessage(friendlyError(error));
    } finally {
      _endOperation();
    }
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool filled = false,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    if (filled) {
      return FilledButton(
        onPressed: busy ? null : onPressed,
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: busy ? null : onPressed,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('پشتیبان‌گیری و بازیابی'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const NoticeCard(
                text:
                    'پشتیبان شامل پروفایل، برنامه‌ها، امتحان‌ها، '
                    'فلش‌کارت‌ها، گفت‌وگوها، جلسه‌های تدریس، '
                    'یادآورها و گزارش‌های مشاوره است. '
                    'کیسه پرهای سیمرغ و سابقه خرید در پشتیبان نیستند.',
                icon: Icons.backup_outlined,
              ),
              const SizedBox(height: 8),
              const NoticeCard(
                text:
                    'پشتیبان متن ساده و شامل اطلاعات خصوصی توست. '
                    'آن را فقط در جای امنی نگه دار و با دیگران به اشتراک نگذار.',
                warning: true,
              ),
              const SizedBox(height: 8),

              _buildActionButton(
                onPressed: saveBackupFile,
                icon: Icons.save_alt_outlined,
                label: 'ذخیره فایل پشتیبان',
                filled: true,
              ),
              const SizedBox(height: 8),

              _buildActionButton(
                onPressed: openBackupFile,
                icon: Icons.folder_open_outlined,
                label: 'انتخاب فایل پشتیبان',
              ),
              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: busy ? null : copyBackup,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('کپی متن پشتیبان (روش جایگزین)'),
              ),

              const SizedBox(height: 24),

              const Text(
                'بازیابی',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: input,
                enabled: !busy,
                minLines: 4,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'متن پشتیبان را اینجا بچسبان',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  helperText: 'حداکثر حجم پشتیبان: ۵ مگابایت',
                ),
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : paste,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('چسباندن'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: busy ? null : restore,
                      child: const Text('بازیابی'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const Text(
                'نکته: بازیابی اطلاعات فعلی را جایگزین می‌کند. '
                'پیش از انجام آن، از اطلاعات فعلی نسخه پشتیبان بگیر.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),

          if (busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black12,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 18,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('لطفاً کمی صبر کن...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
