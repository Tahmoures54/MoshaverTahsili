import 'dart:async';

import 'package:flutter/material.dart';
import 'ai_advisor_service.dart';
import 'credit_shop_page.dart';
import 'education_store.dart';
import 'study_pages.dart' show newId;
import 'ui.dart';

class AdvisorPage extends StatefulWidget {
  const AdvisorPage({super.key, required this.store, this.service});
  final EducationStore store;
  final AiAdvisorService? service;
  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends State<AdvisorPage> {
  final input = TextEditingController();
  late final bool _ownsService = widget.service == null;
  late final AiAdvisorService service = widget.service ?? AiAdvisorService(store: widget.store);
  late List<Map<String, dynamic>> messages;
  bool busy = false;
  String? error;
  String? retryId;

  @override
  void initState() {
    super.initState();
    messages = widget.store.messages;
    for (final message in messages.reversed) {
      if (message['role'] == 'user' && {'pending', 'failed'}.contains(message['status'])) {
        retryId = message['id']?.toString();
        break;
      }
      if (message['role'] == 'user') break;
    }
  }

  @override
  void dispose() {
    input.dispose();
    if (_ownsService) service.dispose();
    super.dispose();
  }

  Future<void> openShop() async {
    await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CreditShopPage(store: widget.store)));
    if (mounted) setState(() {});
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (busy || text.isEmpty) return;
    if (text.length > EducationStore.maxQuestionLength) {
      setState(() => error = 'پرسش می‌تواند حداکثر ۴۰۰۰ نویسه داشته باشد.');
      return;
    }
    final id = newId('ai');
    final message = {'id': id, 'role': 'user', 'content': text,
      'status': 'pending', 'createdAt': DateTime.now().toIso8601String()};
    setState(() { busy = true; error = null; messages.add(message); });
    try { await widget.store.saveMessages(messages); } on Object catch (value) {
      if (mounted) setState(() { busy = false; messages.removeLast(); error = friendlyError(value); });
      return;
    }
    input.clear();
    await request(id, text, alreadyBusy: true);
  }

  Future<void> request(String id, String text, {bool alreadyBusy = false}) async {
    if (busy && !alreadyBusy) return;
    setState(() { busy = true; error = null; retryId = id; });
    final history = messages.where((m) => m['id'] != id).toList();
    try {
      final answer = await service.ask(profile: widget.store.profile, history: history,
          question: text, requestId: id);
      if (!mounted) return;
      setState(() {
        for (final message in messages) { if (message['id'] == id) message['status'] = 'completed'; }
        messages.removeWhere((m) => m['id'] == '$id-answer');
        messages.add({'id': '$id-answer', 'role': 'assistant', 'content': answer,
          'status': 'completed', 'createdAt': DateTime.now().toIso8601String()});
        retryId = null;
      });
      await widget.store.saveMessages(messages);
    } on Object catch (value) {
      if (!mounted) return;
      setState(() {
        error = friendlyError(value);
        for (final message in messages) { if (message['id'] == id) message['status'] = 'failed'; }
      });
      try { await widget.store.saveMessages(messages); } on Object {
        // The wallet still holds the completed answer/refund. A storage error
        // must never turn a real answer into a fabricated one.
      }
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> clearChat() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('گفت‌وگو پاک شود؟'), content: const Text('تاریخچه گفت‌وگو پاک می‌شود؛ اعتبار و سابقه خرید تغییر نمی‌کند.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک کردن'))]));
    if (confirmed != true || !mounted) return;
    try { await widget.store.saveMessages([]); if (mounted) setState(() { messages = []; error = null; retryId = null; }); }
    on Object catch (value) { if (mounted) showMessage(context, friendlyError(value)); }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: CreditSummary(store: widget.store, onShop: busy ? null : openShop)),
    if (!service.isConfigured) const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
      child: NoticeCard(text: 'مشاور هوش مصنوعی در این نسخه پیکربندی نشده است. برنامه مطالعه، نمرات، مرور و راهنمای روش مطالعه بدون اینترنت کار می‌کنند.', warning: true)),
    if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: NoticeCard(text: error!, icon: Icons.error_outline, warning: true)),
    Expanded(child: messages.isEmpty ? ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 18), const Icon(Icons.auto_awesome, color: blue, size: 46),
      const SizedBox(height: 14), const Text('سلام! همراه یادگیری تو هستم.', textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      const SizedBox(height: 8), const Text('درباره درس‌ها، برنامه‌ریزی و مسیر تحصیلی بپرس. پاسخ هوش مصنوعی ممکن است اشتباه باشد؛ موضوع‌های مهم را با معلم یا مشاور مدرسه بررسی کن.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.blueGrey, height: 1.8)),
      const SizedBox(height: 20),
      for (final prompt in ['برای این هفته یک برنامه مطالعه واقع‌بینانه پیشنهاد بده.', 'چطور نقاط قوت و ضعف درسی‌ام را بشناسم؟', 'برای بهتر شدن تمرکزم چه تمرین‌هایی انجام دهم؟'])
        Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton(
            onPressed: busy ? null : () => setState(() => input.text = prompt), child: Text(prompt, textAlign: TextAlign.right))),
    ]) : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12), itemCount: messages.length + (busy ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return const Padding(padding: EdgeInsets.all(12), child: Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12),
              Expanded(child: Text('در حال دریافت پاسخ… درخواست ناموفق هزینه نهایی ندارد.')),
            ]));
          }
          final message = messages[index];
          final user = message['role'] == 'user';
          final failed = message['status'] == 'failed' || message['status'] == 'pending';
          return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86),
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: user ? blue : Colors.white, borderRadius: BorderRadius.circular(18),
                  border: user ? null : Border.all(color: const Color(0xFFE3EAF2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user ? 'پرسش تو' : 'مشاور هوش مصنوعی', style: TextStyle(fontSize: 11, color: user ? Colors.white70 : teal, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(message['content'].toString(), style: TextStyle(color: user ? Colors.white : navy, height: 1.8)),
                if (user && failed) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
                    message['status'] == 'pending' ? 'پاسخ این درخواست هنوز ثبت نشده است.' : 'این درخواست کامل نشد.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12))),
                if (user && failed && retryId == message['id'] && !busy)
                  TextButton.icon(
                      key: const ValueKey('advisor-retry-request'),
                      onPressed: () => request(
                          message['id'].toString(), message['content'].toString()),
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('تلاش دوباره همین درخواست', style: TextStyle(color: Colors.white))),
              ])));
        })),
    Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: SafeArea(top: false,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(tooltip: 'پاک کردن گفت‌وگو', onPressed: busy || messages.isEmpty ? null : clearChat, icon: const Icon(Icons.delete_sweep_outlined)),
        Expanded(child: TextField(controller: input, enabled: !busy, minLines: 1, maxLines: 4,
          maxLength: EducationStore.maxQuestionLength, textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: 'پرسشت را اینجا بنویس…', counterText: ''))),
        const SizedBox(width: 8),
        IconButton.filled(tooltip: 'ارسال پرسش', onPressed: busy ? null : send, icon: const Icon(Icons.send_rounded)),
      ]))),
  ]);
}
