import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

/// Local backup and restore through the clipboard. No file permission, no
/// network. The AI wallet is excluded on purpose, so a file cannot mint credits.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.store});
  final EducationStore store;
  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  static const backupChannel = MethodChannel('ir.moshaver.tahsili/backup');
  final input = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> saveBackupFile() async {
    setState(() => busy = true);
    try {
      final raw = await widget.store.exportBackup();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await backupChannel.invokeMethod<bool>('saveBackup', {
        'content': raw,
        'fileName': 'simorgh-backup-$date.json',
      });
      if (mounted && saved == true) {
        showMessage(context, 'فایل پشتیبان ذخیره شد.');
      }
    } on PlatformException catch (error) {
      if (mounted) showMessage(context, error.message ?? 'ذخیره فایل انجام نشد.');
    } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openBackupFile() async {
    setState(() => busy = true);
    try {
      final raw = await backupChannel.invokeMethod<String>('openBackup');
      if (!mounted || raw == null) return;
      WorkspaceBackup.decode(raw);
      input.text = raw;
      showMessage(context, 'فایل پشتیبان خوانده شد؛ برای تأیید و بازیابی اقدام کن.');
    } on BackupFormatException catch (error) {
      if (mounted) showMessage(context, error.toString());
    } on PlatformException catch (error) {
      if (mounted) showMessage(context, error.message ?? 'خواندن فایل انجام نشد.');
    } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copyBackup() async {
    setState(() => busy = true);
    try {
      final raw = await widget.store.exportBackup();
      await Clipboard.setData(ClipboardData(text: raw));
      if (mounted) showMessage(context, 'متن پشتیبان کپی شد.');
    } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    input.text = data?.text ?? '';
  }

  Future<void> restore() async {
    final raw = input.text.trim();
    try {
      WorkspaceBackup.decode(raw);
    } on BackupFormatException catch (error) {
      if (mounted) showMessage(context, error.toString());
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بازیابی پشتیبان؟'),
        content: const Text('اطلاعات تحصیلی فعلی این گوشی با محتوای پشتیبان جایگزین می‌شود. '
            'کیف اعتبار و سابقه خرید تغییر نمی‌کنند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بازیابی')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final sections = await widget.store.importBackup(raw);
      input.clear();
      if (mounted) showMessage(context, 'بازیابی انجام شد؛ ${faNumber(sections)} بخش بازیابی شد.');
    } on BackupFormatException catch (error) {
      if (mounted) showMessage(context, error.toString());
    } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('پشتیبان‌گیری و بازیابی')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const NoticeCard(
            text: 'پشتیبان شامل پروفایل، برنامه‌ها، امتحان‌ها، فلش‌کارت‌ها و گزارش‌های مشاوره است. '
                'کیف اعتبار و سابقه خرید در پشتیبان نیستند.',
            icon: Icons.backup_outlined,
          ),
          const NoticeCard(
            text: 'پشتیبان متن ساده و شامل اطلاعات خصوصی توست. آن را فقط در جای امنی نگه دار '
                'و با دیگران به اشتراک نگذار.',
            warning: true,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : saveBackupFile,
            icon: const Icon(Icons.save_alt_outlined),
            label: const Text('ذخیره فایل پشتیبان'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : openBackupFile,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('انتخاب فایل پشتیبان'),
          ),
          TextButton.icon(
            onPressed: busy ? null : copyBackup,
            icon: const Icon(Icons.copy_outlined),
            label: const Text('کپی متن پشتیبان (روش جایگزین)'),
          ),
          const SizedBox(height: 24),
          const Text('بازیابی', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          TextField(
            controller: input,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'متن پشتیبان را اینجا بچسبان',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: busy ? null : paste,
              icon: const Icon(Icons.content_paste),
              label: const Text('چسباندن'),
            )),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(
              onPressed: busy ? null : restore,
              child: const Text('بازیابی'),
            )),
          ]),
        ]),
      );
}
