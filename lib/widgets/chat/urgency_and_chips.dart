import 'package:flutter/material.dart';

import '../../models/diagnosis_result.dart';

Color urgencyColor(DiagnosisUrgency urgency) {
  switch (urgency) {
    case DiagnosisUrgency.green:
      return Colors.green;
    case DiagnosisUrgency.yellow:
      return Colors.amber.shade700;
    case DiagnosisUrgency.red:
      return Colors.red;
  }
}

String urgencyLabel(DiagnosisUrgency urgency) {
  switch (urgency) {
    case DiagnosisUrgency.green:
      return 'وضعیت عادی';
    case DiagnosisUrgency.yellow:
      return 'نیاز به توجه';
    case DiagnosisUrgency.red:
      return 'فوری — احتیاط کن';
  }
}

IconData urgencyIcon(DiagnosisUrgency urgency) {
  switch (urgency) {
    case DiagnosisUrgency.green:
      return Icons.check_circle_rounded;
    case DiagnosisUrgency.yellow:
      return Icons.warning_amber_rounded;
    case DiagnosisUrgency.red:
      return Icons.error_rounded;
  }
}

class UrgencyBadge extends StatelessWidget {
  const UrgencyBadge({super.key, required this.urgency});
  final DiagnosisUrgency urgency;

  @override
  Widget build(BuildContext context) {
    final color = urgencyColor(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(urgencyIcon(urgency), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            urgencyLabel(urgency),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.confidence});
  final DiagnosisConfidence confidence;

  String get _label {
    switch (confidence) {
      case DiagnosisConfidence.high:
        return 'اطمینان بالا';
      case DiagnosisConfidence.medium:
        return 'اطمینان متوسط';
      case DiagnosisConfidence.low:
        return 'اطمینان کم';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
    );
  }
}

class ProbabilityChip extends StatelessWidget {
  const ProbabilityChip({super.key, required this.level});
  final ProbabilityLevel level;

  Color get _color {
    switch (level) {
      case ProbabilityLevel.high:
        return Colors.deepOrange;
      case ProbabilityLevel.medium:
        return Colors.orange;
      case ProbabilityLevel.low:
        return Colors.blueGrey;
    }
  }

  String get _label {
    switch (level) {
      case ProbabilityLevel.high:
        return 'احتمال بالا';
      case ProbabilityLevel.medium:
        return 'احتمال متوسط';
      case ProbabilityLevel.low:
        return 'احتمال کم';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label, style: TextStyle(fontSize: 10.5, color: _color, fontWeight: FontWeight.w600)),
    );
  }
}
