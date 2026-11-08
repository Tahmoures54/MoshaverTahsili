import 'package:flutter_test/flutter_test.dart';

import 'package:smart_mechanic/controllers/chat_controller.dart';
import 'package:smart_mechanic/models/chat_message.dart';
import 'package:smart_mechanic/models/diagnosis_result.dart';
import 'package:smart_mechanic/providers/auth_provider.dart';
import 'package:smart_mechanic/services/api_service.dart';

void main() {
  late ChatController controller;

  setUp(() {
    controller = ChatController(
      carId: 'test-car',
      carName: 'خودروی آزمایشی',
      year: '۱۴۰۲',
      isCustomCar: false,
      apiService: ApiService(),
      authProvider: AuthProvider(ApiService()),
    );
  });

  tearDown(() => controller.dispose());

  test('a legacy questions-mode payload is coerced into a full diagnosis card', () async {
    controller.seedInitial(
      userMessage: 'عقب ماشینم صدا می‌دهد',
      initialResultText: 'بررسی شد.',
      initialResultJson: {
        'responseMode': 'questions',
        'followUpRound': 1,
        'questionOptions': [
          {
            'question': 'صدا در حالت سرد شنیده می‌شود؟',
            'options': ['بله', 'خیر'],
          },
        ],
      },
    );

    // سیاست «پاسخ مستقیم»: حتی اگر بک‌اندِ قدیمی حالت questions بفرستد،
    // کلاینت آن را به کارت تشخیص کامل تبدیل می‌کند تا کاربر وارد دور
    // سؤال پی‌درپی نشود و اعتبارش هدر نرود.
    final last = controller.messages.last;
    expect(last.structured, isNotNull);
    expect(last.structured!.responseMode, ResponseMode.diagnosis);
    expect(last.structured!.followUpRound, 0);
    expect(last.structured!.optionalHints, isNotEmpty);
    expect(last.structured!.optionalHints.first, contains('حالت سرد'));
  });

  test('the user can keep chatting freely while a legacy question card is on screen', () async {
    controller.seedInitial(
      userMessage: 'عقب ماشینم صدا می‌دهد',
      initialResultText: 'بررسی شد.',
      initialResultJson: {
        'responseMode': 'questions',
        'questionOptions': [
          {
            'question': 'صدا در حالت سرد شنیده می‌شود؟',
            'options': ['بله', 'خیر'],
          },
        ],
      },
    );

    // هیچ قفل «منتظر انتخاب گزینه‌ها» وجود ندارد؛ پیام کاربر همیشه
    // پذیرفته و ارسال می‌شود (در تست بدون توکن، با ۴۰۱ مدیریت‌شده تمام می‌شود).
    await controller.sendUserMessage('صدا بیشتر در پیچ‌ها شنیده می‌شود');

    expect(
      controller.messages.any(
        (message) =>
            message.role == MessageRole.user &&
            message.text.contains('پیچ'),
      ),
      isTrue,
    );
    expect(controller.isTyping, isFalse);
    expect(controller.messages.last.role, MessageRole.system);
    expect(controller.conversationHistory.map((m) => m['role']).toList(),
        containsAllInOrder(['user', 'assistant', 'user']));
    expect(controller.conversationHistory.first['content'],
        'عقب ماشینم صدا می‌دهد');
    expect(controller.conversationHistory[1]['content'], 'بررسی شد.');
    expect(controller.conversationHistory.last['content'],
        'صدا بیشتر در پیچ‌ها شنیده می‌شود');
  });
}
