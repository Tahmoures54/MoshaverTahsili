import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../models/diagnosis_result.dart';
import '../../providers/auth_provider.dart';
import '../../services/share_service.dart';
import 'urgency_and_chips.dart';

/// نمایش غنی نتیجهٔ تشخیص — متن کامل، فونت بزرگ و خوانا.
class DiagnosisResultCard extends StatelessWidget {
  const DiagnosisResultCard({
    super.key,
    required this.result,
    this.supplementalText,
    this.onSuggestionTap,
    this.carName,
    this.year,
  });

  final DiagnosisResult result;
  final String? supplementalText;
  final ValueChanged<String>? onSuggestionTap;
  final String? carName;
  final String? year;

  String? get _garagePromoText {
    final text = supplementalText;
    if (text == null) return null;
    const marker = '## 🔧 تعمیرگاه‌های پیشنهادی';
    final start = text.indexOf(marker);
    if (start < 0) return null;
    return text.substring(start).trim();
  }

  /// متن کامل نتیجه برای اشتراک — کوتاه نمی‌شود.
  String get _shareableText {
    final raw = supplementalText ?? '';
    const marker = '## 🔧 تعمیرگاه‌های پیشنهادی';
    final cut = raw.indexOf(marker);
    var body = (cut >= 0 ? raw.substring(0, cut) : raw).trim();
    body = DiagnosisPolicy.stripDirective(body);
    if (body.isEmpty) {
      body = [
        if (result.statusSummary.isNotEmpty) result.statusSummary,
        ...result.causes.map((c) => '• ${c.title}${c.why.isNotEmpty ? ': ${c.why}' : ''}'),
        if (result.nextStep.isNotEmpty) result.nextStep,
      ].join('\n');
    }
    return body;
  }

  Future<void> _shareResult(BuildContext context) async {
    try {
      final auth = context.read<AuthProvider>();
      await ShareService.shareDiagnosis(
        result: _shareableText,
        carName: carName,
        year: year,
        referralCode: auth.referralCode,
      );
    } catch (e) {
      debugPrint('[DiagnosisResultCard] share failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hints = result.optionalHints;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // کارت روشن و خوانا روی پس‌زمینه گرم؛ در حالت تاریک نیز سطح مشخصی دارد.
        color: theme.brightness == Brightness.light
            ? Colors.white.withOpacity(0.97)
            : theme.colorScheme.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withOpacity(0.22),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withOpacity(
              theme.brightness == Brightness.light ? 0.07 : 0.16,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.car_repair_rounded,
                  color: theme.colorScheme.primary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'گزارش عیب‌یابی',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'جمع‌بندی فنی بر اساس علائم اعلام‌شده',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              UrgencyBadge(urgency: result.urgency),
              ConfidenceChip(confidence: result.confidence),
            ],
          ),
          if (result.safeToDrive == false) ...[
            const SizedBox(height: 12),
            _SafetyBanner(text: 'توصیه می‌شود با این وضعیت رانندگی نکنید.'),
          ],
          if (result.statusSummary.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.075),
                borderRadius: BorderRadius.circular(13),
                border: Border(
                  right: BorderSide(
                    color: theme.colorScheme.primary.withOpacity(0.8),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.summarize_rounded,
                          size: 19, color: theme.colorScheme.primary),
                      const SizedBox(width: 7),
                      Text(
                        'جمع‌بندی',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  MarkdownBody(
                    data: result.statusSummary,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: TextStyle(
                        fontSize: 17,
                        height: 1.8,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      strong: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                      listBullet: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...result.warnings.map((w) => _WarningLine(text: w)),
          ],
          if (result.causes.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'علت‌های محتمل:',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...result.causes.map((c) => _CauseTile(cause: c)),
          ],
          if (hints.isNotEmpty) ...[
            const SizedBox(height: 12),
            _OptionalHintsSection(hints: hints),
          ],
          if (result.mechanicQuestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _MechanicChecklist(items: result.mechanicQuestions),
          ],
          if (result.nextStep.isNotEmpty) ...[
            const SizedBox(height: 14),
            _NextStepBox(text: result.nextStep),
          ],
          const SizedBox(height: 14),
          _ContinueChatSection(
            onSuggestionTap: onSuggestionTap,
            onShare: () => _shareResult(context),
          ),
          if (result.footer.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(
              result.footer,
              style: TextStyle(fontSize: 15, height: 1.65, color: theme.hintColor),
            ),
          ],
          if (_garagePromoText != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.primary.withOpacity(0.25)),
              ),
              child: MarkdownBody(
                data: _garagePromoText!,
                shrinkWrap: true,
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: const TextStyle(fontSize: 16, height: 1.7),
                  h2: TextStyle(
                    fontSize: 17,
                    height: 1.55,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                  listBullet: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContinueChatSection extends StatelessWidget {
  const _ContinueChatSection({this.onSuggestionTap, this.onShare});

  final ValueChanged<String>? onSuggestionTap;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DiagnosisPolicy.encouragementText,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.75,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DiagnosisPolicy.followUpSuggestions
                .map(
                  (suggestion) => ActionChip(
                    label: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    avatar: Icon(Icons.arrow_forward_rounded,
                        size: 15, color: theme.colorScheme.primary),
                    backgroundColor: theme.colorScheme.surface,
                    side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.35)),
                    onPressed: onSuggestionTap == null ? null : () => onSuggestionTap!(suggestion),
                  ),
                )
                .toList(),
          ),
          if (onShare != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text(
                  'اشتراک‌گذاری این نتیجه',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionalHintsSection extends StatelessWidget {
  const _OptionalHintsSection({required this.hints});

  final List<String> hints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اگر این جزئیات را هم بگویی، پاسخ بعدی دقیق‌تر می‌شود (اختیاری):',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...hints.asMap().entries.map(
                (e) => _NumberedLine(index: e.key + 1, text: e.value),
              ),
        ],
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dangerous_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                height: 1.55,
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningLine extends StatelessWidget {
  const _WarningLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 15.5, height: 1.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedLine extends StatelessWidget {
  const _NumberedLine({required this.index, required this.text});
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$index.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(text, style: const TextStyle(fontSize: 16, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

class _CauseTile extends StatelessWidget {
  const _CauseTile({required this.cause});
  final DiagnosisCause cause;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.045),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  cause.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, height: 1.45),
                ),
              ),
              const SizedBox(width: 8),
              ProbabilityChip(level: cause.probability),
            ],
          ),
          if (cause.why.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownBody(
              data: cause.why,
              selectable: true,
              softLineBreak: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: TextStyle(
                  fontSize: 15.5,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                strong: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
          if (cause.diyCheck != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.build_circle_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: MarkdownBody(
                      data: cause.diyCheck!,
                      selectable: true,
                      softLineBreak: true,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                        p: TextStyle(
                          fontSize: 15.5,
                          height: 1.65,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        strong: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ),
                ),
              ],
            ),
          ],
          if (cause.costEstimate != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              cause.costEstimate!,
              style: const TextStyle(
                fontSize: 15.5,
                height: 1.55,
                color: Colors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MechanicChecklist extends StatelessWidget {
  const _MechanicChecklist({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'چک‌لیست برای تعمیرگاه',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'کپی چک‌لیست',
                onPressed: () {
                  final text = items.map((e) => '- $e').join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('چک‌لیست کپی شد')));
                },
              ),
            ],
          ),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: SelectableText(
                      e,
                      style: const TextStyle(fontSize: 15.5, height: 1.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStepBox extends StatelessWidget {
  const _NextStepBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  color: Theme.of(context).colorScheme.primary, size: 20),
              const SizedBox(width: 7),
              Text(
                'اقدام پیشنهادی',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          MarkdownBody(
            data: text,
            selectable: true,
            softLineBreak: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.75,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              strong: TextStyle(
                fontWeight: FontWeight.w900,
                color: Theme.of(context).colorScheme.primary,
              ),
              listBullet: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
