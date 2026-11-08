import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'education/education_store.dart';
import 'education/ai_advisor_service.dart';
import 'education/credit_shop_page.dart';

// ─── رنگ‌های برند ───────────────────────────────────────
const Color _navy = Color(0xFF17324D);
const Color _blue = Color(0xFF2867A8);
const Color _teal = Color(0xFF2C9C91);
const Color _pale = Color(0xFFF4F7FB);

// ─── تابع کمکی: پیام خطای کاربرپسند ────────────────────
String _userMessage(Object error) {
  if (error is AiException) return error.message;
  if (error is BazaarBillingException) return error.message;
  return error
      .toString()
      .replaceFirst(RegExp(r'^[A-Za-z]+Exception:\s*'), '');
}

// ─── تابع کمکی: تبدیل ارقام فارسی به انگلیسی ───────────
String _digitsToEnglish(String value) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const en = '0123456789';
  var result = value;
  for (var i = 0; i < fa.length; i++) {
    result = result.replaceAll(fa[i], en[i]);
  }
  return result;
}

// ═══════════════════════════════════════════════════════════
//  EducationApp – نقطه ورود اصلی اپ
// ═══════════════════════════════════════════════════════════
class EducationApp extends StatefulWidget {
  const EducationApp({super.key});

  @override
  State<EducationApp> createState() => _EducationAppState();
}

class _EducationAppState extends State<EducationApp>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'مشاور هوشمند تحصیلی',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          centerTitle: true,
          bottom: TabBar(
            controller: _tab,
            indicatorColor: _teal,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.home_rounded), text: 'خانه'),
              Tab(icon: Icon(Icons.calendar_today_rounded), text: 'برنامه'),
              Tab(icon: Icon(Icons.quiz_rounded), text: 'آزمون'),
              Tab(icon: Icon(Icons.style_rounded), text: 'فلش‌کارت'),
              Tab(icon: Icon(Icons.smart_toy_rounded), text: 'مشاور'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: const [
            HomePage(),
            PlannerPage(),
            ExamsPage(),
            CardsPage(),
            AdvisorPage(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ۱) صفحه خانه
// ═══════════════════════════════════════════════════════════
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EducationStore>();
    final profile = store.profile;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── کارت خوش‌آمدگویی ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_blue, _teal],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سلام ${profile['name'] ?? 'دانش‌آموز'} عزیز! 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'پایه ${profile['grade'] ?? '—'}  •  '
                  'رشته ${profile['field'] ?? '—'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── آمار سریع ──
          Row(
            children: [
              _StatCard(
                icon: Icons.task_alt_rounded,
                label: 'تکالیف',
                value: '${store.tasks.length}',
                color: _blue,
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.quiz_rounded,
                label: 'آزمون',
                value: '${store.exams.length}',
                color: _teal,
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.style_rounded,
                label: 'کارت',
                value: '${store.cards.length}',
                color: _navy,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── اعتبار هوش مصنوعی ──
          Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.amber, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'اعتبار مشاور هوشمند',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          store.aiWallet > 0
                              ? '${store.aiWallet} پیام باقی‌مانده'
                              : 'اعتبار رایگان: ${store.freeAiUsed}/${EducationStore.freeAiLimit}',
                          style: TextStyle(
                            color: store.aiWallet > 0 ? _teal : Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider.value(
                            value: store,
                            child: const CreditShopPage(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                    label: const Text('خرید'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── میانبرها ──
          const Text(
            'میانبرها',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ShortcutChip(
                icon: Icons.school_rounded,
                label: 'انتخاب رشته',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CareerPage()),
                  );
                },
              ),
              _ShortcutChip(
                icon: Icons.tips_and_updates_rounded,
                label: 'نکات مطالعه',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudyTipsPage()),
                  );
                },
              ),
              _ShortcutChip(
                icon: Icons.person_rounded,
                label: 'ویرایش پروفایل',
                onTap: () => _showProfileDialog(context, store),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context, EducationStore store) {
    final nameCtrl =
        TextEditingController(text: store.profile['name'] as String? ?? '');
    final gradeCtrl =
        TextEditingController(text: store.profile['grade'] as String? ?? '');
    final fieldCtrl =
        TextEditingController(text: store.profile['field'] as String? ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش پروفایل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'نام'),
            ),
            TextField(
              controller: gradeCtrl,
              decoration: const InputDecoration(labelText: 'پایه تحصیلی'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: fieldCtrl,
              decoration: const InputDecoration(labelText: 'رشته'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              store.updateProfile(
                name: nameCtrl.text.trim(),
                grade: _digitsToEnglish(gradeCtrl.text.trim()),
                field: fieldCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(value,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: _blue),
      label: Text(label),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: _blue, width: 0.5),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ۲) صفحه برنامه درسی
// ═══════════════════════════════════════════════════════════
class PlannerPage extends StatelessWidget {
  const PlannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EducationStore>();
    final tasks = store.tasks;

    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('هنوز تکلیفی ثبت نشده',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showAddTask(context, store),
              icon: const Icon(Icons.add),
              label: const Text('افزودن تکلیف'),
              style: FilledButton.styleFrom(backgroundColor: _blue),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _showAddTask(context, store),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('تکلیف جدید'),
              style: FilledButton.styleFrom(backgroundColor: _blue),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: tasks.length,
            itemBuilder: (context, i) {
              final task = tasks[i];
              final done = task['done'] == true;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: CheckboxListTile(
                  value: done,
                  onChanged: (v) => store.toggleTask(i),
                  title: Text(
                    task['title'] as String? ?? '',
                    style: TextStyle(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? Colors.grey : null,
                    ),
                  ),
                  subtitle: Text(
                    '📅 ${task['date'] ?? '—'}  •  ⏰ ${task['duration'] ?? '—'} دقیقه',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  activeColor: _teal,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddTask(BuildContext context, EducationStore store) {
    showDialog(
      context: context,
      builder: (ctx) => _AddTaskDialog(
        onAdd: (title, date, duration) {
          store.addTask(title: title, date: date, duration: duration);
        },
      ),
    );
  }
}

class _AddTaskDialog extends StatefulWidget {
  final void Function(String title, String date, int duration) onAdd;
  const _AddTaskDialog({required this.onAdd});

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _titleCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _durCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _dateCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تکلیف جدید'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'عنوان تکلیف'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dateCtrl,
            decoration: const InputDecoration(
              labelText: 'تاریخ (مثلاً ۱۴۰۴/۰۳/۲۵)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _durCtrl,
            decoration: const InputDecoration(labelText: 'مدت (دقیقه)'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            if (title.isEmpty) return;
            widget.onAdd(
              title,
              _dateCtrl.text.trim(),
              int.tryParse(_digitsToEnglish(_durCtrl.text.trim())) ?? 30,
            );
            Navigator.pop(context);
          },
          child: const Text('افزودن'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ۳) صفحه آزمون‌ها
// ═══════════════════════════════════════════════════════════
class ExamsPage extends StatelessWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EducationStore>();
    final exams = store.exams;

    if (exams.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.quiz_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('آزمونی ثبت نشده',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showAddExam(context, store),
              icon: const Icon(Icons.add),
              label: const Text('افزودن آزمون'),
              style: FilledButton.styleFrom(backgroundColor: _teal),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _showAddExam(context, store),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('آزمون جدید'),
              style: FilledButton.styleFrom(backgroundColor: _teal),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: exams.length,
            itemBuilder: (context, i) {
              final exam = exams[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: _teal,
                    child: Icon(Icons.quiz_rounded, color: Colors.white),
                  ),
                  title: Text(exam['subject'] as String? ?? ''),
                  subtitle: Text(
                    '📅 ${exam['date'] ?? '—'}  •  '
                    'نمره: ${exam['score'] ?? '—'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => store.removeExam(i),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddExam(BuildContext context, EducationStore store) {
    showDialog(
      context: context,
      builder: (ctx) => _AddExamDialog(
        onAdd: (subject, date, score) {
          store.addExam(subject: subject, date: date, score: score);
        },
      ),
    );
  }
}

class _AddExamDialog extends StatefulWidget {
  final void Function(String subject, String date, String score) onAdd;
  const _AddExamDialog({required this.onAdd});

  @override
  State<_AddExamDialog> createState() => _AddExamDialogState();
}

class _AddExamDialogState extends State<_AddExamDialog> {
  final _subCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _scoreCtrl = TextEditingController();

  @override
  void dispose() {
    _subCtrl.dispose();
    _dateCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('آزمون جدید'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _subCtrl,
            decoration: const InputDecoration(labelText: 'درس'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dateCtrl,
            decoration: const InputDecoration(labelText: 'تاریخ'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _scoreCtrl,
            decoration: const InputDecoration(labelText: 'نمره (اختیاری)'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () {
            final sub = _subCtrl.text.trim();
            if (sub.isEmpty) return;
            widget.onAdd(
              sub,
              _dateCtrl.text.trim(),
              _scoreCtrl.text.trim(),
            );
            Navigator.pop(context);
          },
          child: const Text('افزودن'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ۴) صفحه فلش‌کارت‌ها
// ═══════════════════════════════════════════════════════════
class CardsPage extends StatelessWidget {
  const CardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EducationStore>();
    final cards = store.cards;

    if (cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            const Text('فلش‌کارتی ساخته نشده',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showAddCard(context, store),
              icon: const Icon(Icons.add),
              label: const Text('ساخت فلش‌کارت'),
              style: FilledButton.styleFrom(backgroundColor: _navy),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _showAddCard(context, store),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('کارت جدید'),
              style: FilledButton.styleFrom(backgroundColor: _navy),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: cards.length,
            itemBuilder: (context, i) {
              final card = cards[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                child: ExpansionTile(
                  leading: const Icon(Icons.style_rounded, color: _navy),
                  title: Text(card['front'] as String? ?? ''),
                  subtitle: Text(
                    'تکرار: ${card['interval'] ?? 1} روز',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        card['back'] as String? ?? '',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    ButtonBar(
                      children: [
                        TextButton(
                          onPressed: () {
                            // کپی امن Map برای جلوگیری از mutation مستقیم
                            final updated = Map<String, dynamic>.from(card)
                              ..['interval'] =
                                  ((card['interval'] as int?) ?? 1) * 2;
                            store.updateCard(i, updated);
                          },
                          child: const Text('✅ بلدم'),
                        ),
                        TextButton(
                          onPressed: () {
                            final updated = Map<String, dynamic>.from(card)
                              ..['interval'] = 1;
                            store.updateCard(i, updated);
                          },
                          child: const Text('🔄 مرور دوباره'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => store.removeCard(i),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddCard(BuildContext context, EducationStore store) {
    showDialog(
      context: context,
      builder: (ctx) => _AddCardDialog(
        onAdd: (front, back) {
          store.addCard(front: front, back: back);
        },
      ),
    );
  }
}

class _AddCardDialog extends StatefulWidget {
  final void Function(String front, String back) onAdd;
  const _AddCardDialog({required this.onAdd});

  @override
  State<_AddCardDialog> createState() => _AddCardDialogState();
}

class _AddCardDialogState extends State<_AddCardDialog> {
  final _frontCtrl = TextEditingController();
  final _backCtrl = TextEditingController();

  @override
  void dispose() {
    _frontCtrl.dispose();
    _backCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فلش‌کارت جدید'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _frontCtrl,
            decoration: const InputDecoration(labelText: 'سؤال (رو)'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _backCtrl,
            decoration: const InputDecoration(labelText: 'پاسخ (پشت)'),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: () {
            final front = _frontCtrl.text.trim();
            final back = _backCtrl.text.trim();
            if (front.isEmpty || back.isEmpty) return;
            widget.onAdd(front, back);
            Navigator.pop(context);
          },
          child: const Text('ساختن'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ۵) صفحه مشاور هوشمند
// ═══════════════════════════════════════════════════════════
class AdvisorPage extends StatefulWidget {
  const AdvisorPage({super.key});

  @override
  State<AdvisorPage> createState() => _AdvisorPageState();
}

class _AdvisorPageState extends State<AdvisorPage> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _ai = AiAdvisorService();
  bool _loading = false;

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _loading) return;

    final store = context.read<EducationStore>();

    // بررسی اعتبار
    if (store.aiWallet <= 0 && store.freeAiUsed >= EducationStore.freeAiLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('اعتبار مشاور تمام شده. لطفاً بسته بخرید.'),
          backgroundColor: Colors.red.shade700,
          action: SnackBarAction(
            label: 'خرید',
            textColor: Colors.white,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChangeNotifierProvider.value(
                    value: store,
                    child: const CreditShopPage(),
                  ),
                ),
              );
            },
          ),
        ),
      );
      return;
    }

    // افزودن پیام کاربر
    store.addMessage(role: 'user', content: text);
    _msgCtrl.clear();
    _scrollToBottom();

    setState(() => _loading = true);

    try {
      final reply = await _ai.chat(
        userMessage: text,
        history: store.messages,
        profile: store.profile,
      );
      store.addMessage(role: 'assistant', content: reply);

      // کسر اعتبار
      if (store.aiWallet > 0) {
        store.deductAiCredit(1);
      } else {
        store.incrementFreeAiUsed();
      }
    } on AiException catch (e) {
      // خطاهای AiException در تاریخچه ذخیره نمی‌شوند
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_userMessage(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EducationStore>();
    final messages = store.messages;

    return Column(
      children: [
        // ── نوار اعتبار ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _pale,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                store.aiWallet > 0
                    ? '💰 ${store.aiWallet} اعتبار'
                    : '🆓 ${store.freeAiUsed}/${EducationStore.freeAiLimit} رایگان',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (messages.isNotEmpty)
                TextButton.icon(
                  onPressed: () => store.clearMessages(),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('پاک کردن', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
        ),

        // ── لیست پیام‌ها ──
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_toy_rounded,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text(
                        'سؤالت را از مشاور هوشمند بپرس! 🤖',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final msg = messages[i];
                    final isUser = msg['role'] == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        decoration: BoxDecoration(
                          color: isUser ? _blue : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          msg['content'] as String? ?? '',
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // ── نوار ورودی ──
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(color: _teal),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'سؤالت را بنویس...',
                    filled: true,
                    fillColor: _pale,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: _teal,
                child: IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                  onPressed: _loading ? null : _send,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  صفحه انتخاب رشته
// ═══════════════════════════════════════════════════════════
class CareerPage extends StatelessWidget {
  const CareerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fields = [
      {'icon': Icons.engineering, 'title': 'ریاضی فیزیک', 'desc': 'مهندسی، کامپیوتر، معماری'},
      {'icon': Icons.biotech, 'title': 'علوم تجربی', 'desc': 'پزشکی، داروسازی، پرستاری'},
      {'icon': Icons.menu_book, 'title': 'علوم انسانی', 'desc': 'حقوق، روانشناسی، مدیریت'},
      {'icon': Icons.palette, 'title': 'هنر', 'desc': 'گرافیک، سینما، موسیقی'},
      {'icon': Icons.language, 'title': 'زبان‌های خارجی', 'desc': 'مترجمی، آموزش زبان'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('راهنمای انتخاب رشته'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: fields.length,
        itemBuilder: (context, i) {
          final f = fields[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _teal.withOpacity(0.15),
                child: Icon(f['icon'] as IconData, color: _teal),
              ),
              title: Text(f['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(f['desc'] as String),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('برای اطلاعات بیشتر از مشاور هوشمند بپرسید'),
                    backgroundColor: _blue,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  صفحه نکات مطالعه
// ═══════════════════════════════════════════════════════════
class StudyTipsPage extends StatelessWidget {
  const StudyTipsPage({super.key});

  static const _tips = [
    {'emoji': '🍅', 'title': 'تکنیک پومودورو', 'body': '۲۵ دقیقه مطالعه، ۵ دقیقه استراحت. بعد از ۴ دور، ۱۵ دقیقه استراحت بلند.'},
    {'emoji': '🧠', 'title': 'تکرار فاصله‌دار', 'body': 'مطالب را در فواصل زمانی افزایشی مرور کن: ۱ روز، ۳ روز، ۷ روز، ۱۴ روز.'},
    {'emoji': '📝', 'title': 'یادداشت فعال', 'body': 'به جای رونویسی، مطالب را با کلمات خودت خلاصه کن.'},
    {'emoji': '😴', 'title': 'خواب کافی', 'body': 'حداقل ۷ ساعت خواب. حافظه در خواب تثبیت می‌شود.'},
    {'emoji': '📵', 'title': 'حذف حواس‌پرتی', 'body': 'گوشی را در حالت پرواز بگذار و در اتاق دیگری قرار بده.'},
    {'emoji': '🎯', 'title': 'هدف‌گذاری روزانه', 'body': 'هر شب ۳ هدف مشخص برای فردا بنویس.'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نکات مطالعه مؤثر'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tips.length,
        itemBuilder: (context, i) {
          final tip = _tips[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${tip['emoji']}  ${tip['title']}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tip['body'] as String,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
