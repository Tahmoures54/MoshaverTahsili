import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/chat_message.dart';

/// حباب چت با قالب‌بندی متناسب با نقش پیام.
/// پیام‌های دستیار Markdown را پشتیبانی می‌کنند؛ پیام کاربر و خطاها ساده می‌مانند.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.highlighted = false,
    this.onRetry,
    this.onShare,
  });

  final ChatMessage message;
  final bool highlighted;
  final VoidCallback? onRetry;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;

    final bubbleColor = isSystem
        ? Colors.red.withOpacity(0.12)
        : isUser
            ? Colors.orange.withOpacity(0.22)
            : theme.colorScheme.surfaceContainerHighest.withOpacity(0.45);

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
        border: highlighted
            ? Border.all(color: Colors.orange.withOpacity(0.45), width: 1.2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isUser || isSystem)
            SelectableText(
              message.text,
              style: TextStyle(
                height: 1.7,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: isSystem ? Colors.redAccent.shade100 : null,
              ),
            )
          else
            MarkdownBody(
              data: message.text,
              selectable: true,
              softLineBreak: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: TextStyle(
                  height: 1.75,
                  fontSize: 16.5,
                  color: theme.colorScheme.onSurface,
                ),
                h1: TextStyle(
                  fontSize: 21,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
                h2: TextStyle(
                  fontSize: 19,
                  height: 1.55,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
                h3: TextStyle(
                  fontSize: 17,
                  height: 1.55,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
                strong: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
                em: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                listBullet: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.primary,
                ),
                blockquote: TextStyle(
                  fontSize: 15.5,
                  height: 1.7,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                code: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.08),
                ),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                ),
                blockquoteDecoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    right: BorderSide(
                      color: theme.colorScheme.primary.withOpacity(0.65),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          if (!isUser && !isSystem && message.isDiagnosisResult && onShare != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined, size: 17),
                label: const Text('اشتراک‌گذاری پاسخ'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
          if (isSystem && onRetry != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onRetry,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 16, color: Colors.redAccent),
                    SizedBox(width: 6),
                    Text(
                      'تلاش دوباره',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: bubble,
    );
  }
}
