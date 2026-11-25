import 'dart:math' as math;

import 'learning_engine.dart';

/// Conservative, explainable summary of recorded flashcard retrieval.
///
/// Despite the compatibility name "TopicMastery", this class does not prove
/// topic mastery, predict exam success, or measure long-term retention.
///
/// The estimate is a prior-smoothed, weighted retrieval indicator.
/// Reviews of the same card are dependent observations. Per-card evidence
/// is therefore capped before aggregation.
///
/// All probability-like values use the range 0..1.
class TopicMastery {
  const TopicMastery({
    required this.topic,
    required this.estimate,
    required this.lowerBound,
    required this.upperBound,
    required this.evidenceCount,
    required this.successes,
    required this.confidence,
    this.cardCount = 0,
    this.effectiveEvidence = 0.0,
    this.difficultSuccesses = 0,
    this.easySuccesses = 0,
    this.datedEvidenceCount = 0,
    this.latestReviewedAt,
  });

  final String topic;

  /// Smoothed weighted retrieval indicator, not a calibrated probability.
  final double estimate;

  /// Approximate normal band around a pseudo-Beta posterior mean.
  ///
  /// This is not an exact credible interval or a validated coverage interval.
  /// Capping per-card evidence reduces overprecision but does not make
  /// dependent reviews statistically independent.
  final double lowerBound;
  final double upperBound;

  /// Retained valid review records, before evidence weighting and capping.
  final int evidenceCount;

  /// Retained reviews with quality >= 3.
  final int successes;

  /// Plain-language evidence label.
  ///
  /// Depends on review count, distinct identifiable cards and effective
  /// evidence. It is not a statistical confidence level.
  final String confidence;

  /// Number of contributing card identities.
  ///
  /// Cards sharing a non-empty string id are merged.
  /// Cards without an id are treated as separate input records; their
  /// independence or uniqueness cannot be verified.
  final int cardCount;

  /// Sum of evidence weights after recency weighting and per-card capping.
  ///
  /// This is not a statistically validated effective sample size.
  final double effectiveEvidence;

  /// Successful but difficult retrievals: quality == 3.
  final int difficultSuccesses;

  /// Easy retrievals: quality == 5.
  final int easySuccesses;

  /// Retained evidence records with a usable date-time timestamp.
  final int datedEvidenceCount;

  /// Latest timestamp among retained dated reviews, expressed in UTC.
  final DateTime? latestReviewedAt;

  int get failures => evidenceCount - successes;

  /// Unweighted observed success share; null when no evidence exists.
  ///
  /// This differs from estimate because it does not use a prior, quality
  /// weights, recency weights or per-card evidence caps.
  double? get observedRecallRate {
    if (evidenceCount <= 0) return null;
    return successes / evidenceCount;
  }

  double get uncertaintyWidth => upperBound - lowerBound;

  /// Whether at least three card identities contributed evidence.
  ///
  /// This is a descriptive convenience, not a mastery threshold.
  bool get hasMultipleCardEvidence => cardCount >= 3;

  double get datedEvidenceShare {
    if (evidenceCount <= 0) return 0.0;
    return datedEvidenceCount / evidenceCount;
  }
}

const double _priorAlpha = 2.0;
const double _priorBeta = 2.0;

/// Approximately the central 90% normal quantile.
///
/// The resulting band is descriptive, not an exact Bayesian interval.
const double _intervalZ = 1.6448536269514722;

const int _maxTopicLength = 100;
const int _maxCardIdLength = 160;

/// Keeps application history processing bounded per input card record.
const int _maxHistoryRecordsToRead = 5000;

final RegExp _topicWhitespace = RegExp(r'\s+');

final RegExp _unsafeTopicCharacters = RegExp(
  r'[\u0000-\u001F\u007F-\u009F'
  r'\u061C\u200E\u200F\u202A-\u202E'
  r'\u2066-\u2069\uFEFF]',
);

final RegExp _isoTimestampPrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[Tt ]');

String? _normalizedTopic(Object? value) {
  if (value is! String) return null;

  final topic = value
      .replaceAll(_unsafeTopicCharacters, ' ')
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(_topicWhitespace, ' ')
      .trim();

  if (topic.isEmpty || topic.runes.length > _maxTopicLength) {
    return null;
  }

  return topic;
}

String? _cardIdOf(Object? value) {
  if (value is! String) return null;

  final id = value.trim();

  if (id.isEmpty || id.length > _maxCardIdLength) {
    return null;
  }

  return id;
}

/// Accepts only integer quality values in 0..5.
///
/// Numeric strings and floating-point values are deliberately not treated
/// as review evidence.
int? _qualityOf(Object? value) {
  if (value is! int || value < 0 || value > 5) {
    return null;
  }

  return value;
}

/// Parses a stored date-time timestamp and rejects invalid calendar dates.
///
/// Date-only values are not sufficient for timestamp deduplication.
/// Timestamps without a timezone follow Dart's local-time interpretation.
DateTime? _reviewedAtOf(Object? value) {
  if (value is! String) return null;

  final text = value.trim();

  if (text.length > 100) return null;

  final match = _isoTimestampPrefix.firstMatch(text);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  final calendarDate = DateTime.utc(year, month, day);

  // Dart normalizes invalid dates unless explicitly checked.
  if (calendarDate.year != year ||
      calendarDate.month != month ||
      calendarDate.day != day) {
    return null;
  }

  return DateTime.tryParse(text)?.toUtc();
}

double _qualityWeight(int quality) {
  return switch (quality) {
    0 || 1 || 2 => 1.0,
    3 => 0.65,
    4 => 1.0,
    5 => 1.1,
    _ => 0.0,
  };
}

class _ReviewEvidence {
  const _ReviewEvidence({
    required this.quality,
    required this.reviewedAt,
    required this.sequence,
  });

  final int quality;
  final DateTime? reviewedAt;

  /// Input encounter order, used when timestamps are missing or tied.
  final int sequence;

  bool get isSuccess => quality >= 3;
}

class _CardEvidence {
  _CardEvidence({required this.topic});

  final String topic;

  /// One record per usable timestamp for this card identity.
  ///
  /// When the same timestamp appears more than once, the last encountered
  /// valid record wins. This also resolves conflicting quality values.
  final Map<int, _ReviewEvidence> dated = {};

  /// Undated records cannot safely be deduplicated.
  final List<_ReviewEvidence> undated = [];

  void add(_ReviewEvidence evidence) {
    final timestamp = evidence.reviewedAt;

    if (timestamp == null) {
      undated.add(evidence);
    } else {
      dated[timestamp.microsecondsSinceEpoch] = evidence;
    }
  }

  List<_ReviewEvidence> retainedReviews(int maximum) {
    final reviews = <_ReviewEvidence>[...dated.values, ...undated];

    reviews.sort((a, b) {
      final aDate = a.reviewedAt;
      final bDate = b.reviewedAt;

      if (aDate != null && bDate != null) {
        final byDate = bDate.compareTo(aDate);
        if (byDate != 0) return byDate;
      } else if (aDate != null) {
        // Dated evidence is preferred when a history must be shortened.
        return -1;
      } else if (bDate != null) {
        return 1;
      }

      return b.sequence.compareTo(a.sequence);
    });

    if (reviews.length > maximum) {
      reviews.removeRange(maximum, reviews.length);
    }

    return reviews;
  }
}

class _TopicTotals {
  double alpha = _priorAlpha;
  double beta = _priorBeta;

  int count = 0;
  int successes = 0;
  int cardCount = 0;
  int difficultSuccesses = 0;
  int easySuccesses = 0;
  int datedEvidenceCount = 0;

  double effectiveEvidence = 0.0;

  DateTime? latestReviewedAt;
}

String _evidenceLabel(_TopicTotals totals) {
  // A high review count from one card never receives the highest label.
  if (totals.cardCount >= 5 &&
      totals.count >= 15 &&
      totals.effectiveEvidence >= 12.0) {
    return 'شواهد بیشتر';
  }

  if (totals.cardCount >= 3 &&
      totals.count >= 8 &&
      totals.effectiveEvidence >= 6.0) {
    return 'شواهد متوسط';
  }

  return 'شواهد محدود';
}

void _validateOptions({
  required int maxReviewsPerCard,
  required double maxEffectiveEvidencePerCard,
  required DateTime? now,
  required int? lookbackDays,
  required double? halfLifeDays,
}) {
  if (maxReviewsPerCard < 1 || maxReviewsPerCard > _maxHistoryRecordsToRead) {
    throw RangeError.range(
      maxReviewsPerCard,
      1,
      _maxHistoryRecordsToRead,
      'maxReviewsPerCard',
    );
  }

  if (!maxEffectiveEvidencePerCard.isFinite ||
      maxEffectiveEvidencePerCard <= 0 ||
      maxEffectiveEvidencePerCard > _maxHistoryRecordsToRead) {
    throw ArgumentError.value(
      maxEffectiveEvidencePerCard,
      'maxEffectiveEvidencePerCard',
      'Must be finite, greater than zero and at most '
          '$_maxHistoryRecordsToRead.',
    );
  }

  if (lookbackDays != null && (lookbackDays < 1 || lookbackDays > 36500)) {
    throw RangeError.range(lookbackDays, 1, 36500, 'lookbackDays');
  }

  if (halfLifeDays != null &&
      (!halfLifeDays.isFinite || halfLifeDays <= 0 || halfLifeDays > 36500)) {
    throw ArgumentError.value(
      halfLifeDays,
      'halfLifeDays',
      'Must be finite, greater than zero and at most 36500.',
    );
  }

  if (now == null && (lookbackDays != null || halfLifeDays != null)) {
    throw ArgumentError(
      'now is required when lookbackDays or halfLifeDays is provided.',
    );
  }
}

/// Estimates topic-level retrieval from stored flashcard histories.
///
/// Backward-compatible basic use:
///
/// ```dart
/// final results = estimateTopicMastery(cards);
/// ```
///
/// Optional recent-evidence analysis:
///
/// ```dart
/// final results = estimateTopicMastery(
///   cards,
///   now: DateTime.now(),
///   lookbackDays: 90,
///   halfLifeDays: 30,
/// );
/// ```
///
/// Rules:
///
/// * Only non-empty normalized topic strings and integer qualities 0..5
///   contribute evidence.
/// * Qualities 0..2 are unsuccessful; 3..5 are successful.
/// * Quality weights preserve the previous heuristic: 3 => 0.65,
///   5 => 1.1, all other accepted qualities => 1.0.
/// * A Beta(2,2) prior smooths small samples toward 50%.
/// * Total evidence from each card identity is capped. The default cap is
///   5.0, limiting how much repeated reviews of one card can dominate.
/// * Duplicate non-empty string card ids within a topic are merged.
/// * If an id is associated with conflicting topics, its first encountered
///   valid topic wins; subsequent conflicting records are ignored.
/// * Duplicate valid timestamps within one card identity count once.
///   The last encountered valid record wins.
/// * Without ids or timestamps, duplicate detection is necessarily limited.
/// * When [now] is provided, reviews dated after it are excluded.
/// * Undated reviews remain usable unless a lookback or half-life is enabled.
/// * [lookbackDays] uses elapsed 24-hour days, not calendar-day boundaries.
/// * [halfLifeDays] applies exponential evidence decay; this is a heuristic,
///   not a fitted model of memory retention.
/// * At most the final 5000 raw history records of each input card are read.
/// * At most [maxReviewsPerCard] reviews contribute per merged card identity.
///   Dated reviews are retained newest first, followed by undated records
///   newest in input order.
///
/// Results are ordered by estimated retrieval, lowest first.
///
/// No current system clock is read internally: the same data and options
/// yield the same result.
List<TopicMastery> estimateTopicMastery(
  List<Entry> cards, {
  int maxReviewsPerCard = 100,
  double maxEffectiveEvidencePerCard = 5.0,
  DateTime? now,
  int? lookbackDays,
  double? halfLifeDays,
}) {
  _validateOptions(
    maxReviewsPerCard: maxReviewsPerCard,
    maxEffectiveEvidencePerCard: maxEffectiveEvidencePerCard,
    now: now,
    lookbackDays: lookbackDays,
    halfLifeDays: halfLifeDays,
  );

  final referenceTime = now?.toUtc();

  final windowStart = referenceTime != null && lookbackDays != null
      ? referenceTime.subtract(Duration(days: lookbackDays))
      : null;

  final requiresTimestamp = lookbackDays != null || halfLifeDays != null;

  // Prefixes prevent real ids from colliding with generated identities.
  final cardEvidence = <String, _CardEvidence>{};
  final topicById = <String, String>{};

  var sequence = 0;

  for (var cardIndex = 0; cardIndex < cards.length; cardIndex++) {
    final card = cards[cardIndex];
    final topic = _normalizedTopic(card['topic']);
    final history = card['reviewHistory'];

    if (topic == null || history is! List) continue;

    final id = _cardIdOf(card['id']);
    final String identity;

    if (id != null) {
      final previousTopic = topicById[id];

      if (previousTopic != null && previousTopic != topic) {
        continue;
      }

      topicById[id] = topic;
      identity = 'id:$id';
    } else {
      identity = 'anonymous:$cardIndex';
    }

    final bucket = cardEvidence.putIfAbsent(
      identity,
      () => _CardEvidence(topic: topic),
    );

    final firstIndex = math.max(0, history.length - _maxHistoryRecordsToRead);

    for (var index = firstIndex; index < history.length; index++) {
      final raw = history[index];

      if (raw is! Map) continue;

      final quality = _qualityOf(raw['quality']);
      if (quality == null) continue;

      final reviewedAt = _reviewedAtOf(raw['reviewedAt']);

      if (requiresTimestamp && reviewedAt == null) {
        continue;
      }

      if (referenceTime != null &&
          reviewedAt != null &&
          reviewedAt.isAfter(referenceTime)) {
        continue;
      }

      if (windowStart != null &&
          reviewedAt != null &&
          reviewedAt.isBefore(windowStart)) {
        continue;
      }

      bucket.add(
        _ReviewEvidence(
          quality: quality,
          reviewedAt: reviewedAt,
          sequence: sequence++,
        ),
      );
    }
  }

  final totalsByTopic = <String, _TopicTotals>{};

  for (final bucket in cardEvidence.values) {
    final reviews = bucket.retainedReviews(maxReviewsPerCard);

    if (reviews.isEmpty) continue;

    var weightedSuccesses = 0.0;
    var weightedFailures = 0.0;

    var retainedCount = 0;
    var successes = 0;
    var difficultSuccesses = 0;
    var easySuccesses = 0;
    var datedCount = 0;

    DateTime? latestReviewedAt;

    for (final review in reviews) {
      var weight = _qualityWeight(review.quality);

      if (halfLifeDays != null) {
        // Option validation and filtering guarantee both values exist here.
        final age = referenceTime!.difference(review.reviewedAt!);
        final ageDays = age.inMicroseconds / Duration.microsecondsPerDay;

        final decay = math.pow(0.5, ageDays / halfLifeDays).toDouble();

        weight *= decay;
      }

      // Very old evidence can underflow to zero during optional decay.
      if (!weight.isFinite || weight <= 0) continue;

      retainedCount++;

      if (review.isSuccess) {
        weightedSuccesses += weight;
        successes++;
      } else {
        weightedFailures += weight;
      }

      if (review.quality == 3) {
        difficultSuccesses++;
      }

      if (review.quality == 5) {
        easySuccesses++;
      }

      final timestamp = review.reviewedAt;

      if (timestamp != null) {
        datedCount++;

        if (latestReviewedAt == null || timestamp.isAfter(latestReviewedAt)) {
          latestReviewedAt = timestamp;
        }
      }
    }

    final rawWeight = weightedSuccesses + weightedFailures;

    if (retainedCount == 0 || !rawWeight.isFinite || rawWeight <= 0) {
      continue;
    }

    // Scale successes and failures equally, preserving this card's ratio.
    final scale = rawWeight > maxEffectiveEvidencePerCard
        ? maxEffectiveEvidencePerCard / rawWeight
        : 1.0;

    final successEvidence = weightedSuccesses * scale;
    final failureEvidence = weightedFailures * scale;

    final totals = totalsByTopic.putIfAbsent(bucket.topic, _TopicTotals.new);

    totals.alpha += successEvidence;
    totals.beta += failureEvidence;

    totals.count += retainedCount;
    totals.successes += successes;
    totals.cardCount++;

    totals.difficultSuccesses += difficultSuccesses;
    totals.easySuccesses += easySuccesses;
    totals.datedEvidenceCount += datedCount;

    totals.effectiveEvidence += successEvidence + failureEvidence;

    final previousLatest = totals.latestReviewedAt;

    if (latestReviewedAt != null &&
        (previousLatest == null || latestReviewedAt.isAfter(previousLatest))) {
      totals.latestReviewedAt = latestReviewedAt;
    }
  }

  final result = <TopicMastery>[];

  for (final entry in totalsByTopic.entries) {
    final totals = entry.value;
    final total = totals.alpha + totals.beta;

    if (totals.count <= 0 || !total.isFinite || total <= 0) {
      continue;
    }

    final mean = (totals.alpha / total).clamp(0.0, 1.0).toDouble();

    // Algebraically equivalent to alpha*beta / (total²*(total+1)),
    // but avoids unnecessary large intermediate products.
    final variance = mean * (1.0 - mean) / (total + 1.0);
    final margin = _intervalZ * math.sqrt(variance);

    result.add(
      TopicMastery(
        topic: entry.key,
        estimate: mean,
        lowerBound: (mean - margin).clamp(0.0, 1.0).toDouble(),
        upperBound: (mean + margin).clamp(0.0, 1.0).toDouble(),
        evidenceCount: totals.count,
        successes: totals.successes,
        confidence: _evidenceLabel(totals),
        cardCount: totals.cardCount,
        effectiveEvidence: totals.effectiveEvidence,
        difficultSuccesses: totals.difficultSuccesses,
        easySuccesses: totals.easySuccesses,
        datedEvidenceCount: totals.datedEvidenceCount,
        latestReviewedAt: totals.latestReviewedAt,
      ),
    );
  }

  result.sort((a, b) {
    final byEstimate = a.estimate.compareTo(b.estimate);

    return byEstimate != 0 ? byEstimate : a.topic.compareTo(b.topic);
  });

  return List<TopicMastery>.unmodifiable(result);
}
