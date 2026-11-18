import 'learning_engine.dart';

/// A conservative, explainable summary of flashcard retrieval evidence.
/// It is NOT a validated probability of exam success or proof of mastery.
class TopicMastery {
  const TopicMastery({required this.topic, required this.estimate,
    required this.lowerBound, required this.upperBound,
    required this.evidenceCount, required this.successes,
    required this.confidence});
  final String topic;
  final double estimate, lowerBound, upperBound;
  final int evidenceCount, successes;
  final String confidence;
}

/// Estimates topic-level recall from existing SM-2 review history.
/// A Beta(2,2) prior deliberately shrinks small samples toward uncertainty.
/// SM-2 quality 3 means difficult but recalled; 4/5 means successful recall;
/// quality 0..2 means failed/forgotten. Only recorded reviews are evidence.
List<TopicMastery> estimateTopicMastery(List<Entry> cards) {
  final totals = <String, ({double alpha, double beta, int count, int successes})>{};
  for (final card in cards) {
    final topic = card['topic']?.toString().trim() ?? '';
    final history = card['reviewHistory'];
    if (topic.isEmpty || history is! List) continue;
    var current = totals[topic] ?? (alpha: 2.0, beta: 2.0, count: 0, successes: 0);
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
        alpha: current.alpha + (success ? weight : 0),
        beta: current.beta + (success ? 0 : weight),
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
    final mean = value.alpha / total;
    final variance = (value.alpha * value.beta) / (total * total * (total + 1));
    final margin = 1.64 * variance.sqrt();
    result.add(TopicMastery(
      topic: entry.key,
      estimate: mean,
      lowerBound: (mean - margin).clamp(0.0, 1.0).toDouble(),
      upperBound: (mean + margin).clamp(0.0, 1.0).toDouble(),
      evidenceCount: value.count,
      successes: value.successes,
      confidence: value.count >= 15 ? 'شواهد بیشتر' : value.count >= 8 ? 'شواهد متوسط' : 'شواهد محدود',
    ));
  }
  result.sort((a, b) => a.estimate.compareTo(b.estimate));
  return result;
}
