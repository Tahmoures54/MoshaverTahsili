import 'dart:math' as math;

import 'learning_engine.dart';

/// A conservative, explainable summary of flashcard retrieval evidence.
///
/// [estimate] is a smoothed estimate from recorded flashcard reviews. It is
/// not a validated probability of exam success, a measure of long-term
/// retention, or proof that a student has mastered a topic.
class TopicMastery {
  const TopicMastery({
    required this.topic,
    required this.estimate,
    required this.lowerBound,
    required this.upperBound,
    required this.evidenceCount,
    required this.successes,
    required this.confidence,
  });

  final String topic;
  final double estimate;

  /// Approximate 90% normal interval around the Beta posterior mean.
  /// This is a descriptive uncertainty band, not an exact credible interval.
  final double lowerBound;
  final double upperBound;

  /// Number of valid review records, not number of independent cards.
  final int evidenceCount;
  final int successes;

  /// A plain-language label based on review count, not a calibrated
  /// statistical confidence level.
  final String confidence;
}

const double _priorAlpha = 2.0;
const double _priorBeta = 2.0;
const double _intervalZ = 1.64; // Approximately 90% for a normal distribution.
const int _maxTopicLength = 100;

String? _normalizedTopic(Object? value) {
  if (value is! String) return null;
  final topic = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (topic.isEmpty || topic.length > _maxTopicLength) return null;
  return topic;
}

/// Estimates topic-level recall from existing SM-2 review history.
///
/// A Beta(2,2) prior shrinks small samples toward 50% rather than presenting
/// a handful of reviews as certainty. SM-2 quality 3 is treated as a difficult
/// but successful recall; qualities 4/5 are successful; qualities 0..2 are
/// unsuccessful. Only valid, recorded integer quality values are evidence.
///
/// Review records are weighted (quality 3 = 0.65, quality 5 = 1.1), so this is
/// an explainable heuristic Bayesian-style estimate, not a calibrated model.
List<TopicMastery> estimateTopicMastery(List<Entry> cards) {
  final totals = <String, ({
    double alpha,
    double beta,
    int count,
    int successes,
  })>{};

  for (final card in cards) {
    final topic = _normalizedTopic(card['topic']);
    final history = card['reviewHistory'];
    if (topic == null || history is! List) continue;

    var current = totals[topic] ?? (
      alpha: _priorAlpha,
      beta: _priorBeta,
      count: 0,
      successes: 0,
    );

    for (final raw in history) {
      if (raw is! Map) continue;
      final quality = raw['quality'];
      if (quality is! int || quality < 0 || quality > 5) continue;

      final success = quality >= 3;
      final weight = switch (quality) {
        0 || 1 || 2 => 1.0,
        3 => 0.65,
        4 => 1.0,
        5 => 1.1,
        _ => 0.0,
      };

      current = (
        alpha: current.alpha + (success ? weight : 0.0),
        beta: current.beta + (success ? 0.0 : weight),
        count: current.count + 1,
        successes: current.successes + (success ? 1 : 0),
      );
    }

    totals[topic] = current;
  }

  final result = <TopicMastery>[];
  for (final entry in totals.entries) {
    final value = entry.value;
    if (value.count == 0) continue;

    final total = value.alpha + value.beta;
    if (!total.isFinite || total <= 0) continue;

    final mean = value.alpha / total;
    final variance =
        (value.alpha * value.beta) / (total * total * (total + 1));
    final margin = _intervalZ * math.sqrt(variance);

    result.add(TopicMastery(
      topic: entry.key,
      estimate: mean.clamp(0.0, 1.0).toDouble(),
      lowerBound: (mean - margin).clamp(0.0, 1.0).toDouble(),
      upperBound: (mean + margin).clamp(0.0, 1.0).toDouble(),
      evidenceCount: value.count,
      successes: value.successes,
      confidence: value.count >= 15
          ? 'شواهد بیشتر'
          : value.count >= 8
              ? 'شواهد متوسط'
              : 'شواهد محدود',
    ));
  }

  // Weakest estimated recall first; use the topic as a stable tie-breaker.
  result.sort((a, b) {
    final byEstimate = a.estimate.compareTo(b.estimate);
    return byEstimate != 0 ? byEstimate : a.topic.compareTo(b.topic);
  });
  return result;
}
