import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/models/library_question.dart';
import 'package:mathmate/models/user_radar_profile.dart';

/// 题库 API 服务 —— 从服务器获取题目并基于能力画像推荐
class LibraryQuestionService {
  static const String _baseUrl = 'https://mathmate.top/api/library';
  static const int _pageSize = 200;

  /// 已展示过的题目 ID（避免重复推荐）
  final Set<String> _shownIds = <String>{};

  /// 缓存：section → 所有题目
  final Map<String, List<LibraryQuestion>> _cache = <String, List<LibraryQuestion>>{};

  /// 获取指定 section 的全部题目（带缓存）
  Future<List<LibraryQuestion>> fetchBySection(String section) async {
    if (_cache.containsKey(section)) {
      return _cache[section]!;
    }

    final List<LibraryQuestion> all = <LibraryQuestion>[];
    int page = 1;

    while (true) {
      final String url = '$_baseUrl/questions?section=${Uri.encodeComponent(section)}&limit=$_pageSize&page=$page';
      try {
        final http.Response res = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 15));

        if (res.statusCode != 200) break;

        final Map<String, dynamic> data =
            jsonDecode(res.body) as Map<String, dynamic>;
        final List<dynamic> items = data['items'] as List<dynamic>? ?? <dynamic>[];

        for (final dynamic item in items) {
          all.add(LibraryQuestion.fromJson(item as Map<String, dynamic>));
        }

        if (items.length < _pageSize) break;
        page++;
      } catch (e) {
        debugPrint('题库 API 请求失败 ($section): $e');
        break;
      }
    }

    _cache[section] = all;
    return all;
  }

  /// 清空已展示记录（换一批时调用）
  void resetShown() {
    _shownIds.clear();
  }

  /// 核心推荐算法：根据用户能力画像，从服务器题库推荐题目
  ///
  /// 返回 (题目列表, 各维度评分详情) 供 UI 展示。
  /// [profile] 能力画像（携带 dimensionSet 信息）
  /// [grade] 用户年级（用于确定维度→section 标签映射），null 视为 K-12
  /// [targetCount] 期望推荐的题目总数，默认 10 题。
  Future<RecommendationResult> recommend({
    required UserRadarProfile profile,
    int? grade,
    int targetCount = 10,
  }) async {
    final List<String> dimNames = profile.names;
    final Map<String, List<String>> dimTags = UserRadarProfile.dimensionTagsFor(grade);

    final Map<String, double> dimensionScores = <String, double>{};
    for (int i = 0; i < dimNames.length; i++) {
      dimensionScores[dimNames[i]] = profile.scores[i];
    }

    // 1. 计算每个维度的权重（弱项权重大 = 多出题）
    //    强项也有少量题以保持挑战
    final Map<String, double> weights = _calculateWeights(dimensionScores);

    // 2. 按权重分配每个维度的题目数
    final Map<String, int> allocations = _allocateQuestions(weights, targetCount);

    // 3. 为每个维度确定目标难度区间
    final Map<String, DifficultyRange> difficultyRanges =
        _calculateDifficultyRanges(dimensionScores);

    // 4. 从服务器获取对应 section 的题目并筛选
    final List<LibraryQuestion> recommended = <LibraryQuestion>[];
    final Map<String, DimensionRecommendDetail> details =
        <String, DimensionRecommendDetail>{};

    for (final String dim in dimNames) {
      final int needed = allocations[dim] ?? 0;
      if (needed <= 0) continue;

      final List<String> sections = dimTags[dim] ?? <String>[dim];
      final DifficultyRange range = difficultyRanges[dim]!;

      final List<LibraryQuestion> candidates = await _fetchCandidates(
        sections: sections,
        difficultyRange: range,
        excludeIds: _shownIds,
      );

      // 按难度贴近度排序（最接近目标难度的优先）
      candidates.sort((a, b) {
        final double targetMid = (range.min + range.max) / 2;
        return (a.difficulty - targetMid).abs().compareTo((b.difficulty - targetMid).abs());
      });

      final List<LibraryQuestion> selected = candidates.take(needed).toList();
      for (final LibraryQuestion q in selected) {
        _shownIds.add(q.id);
      }
      recommended.addAll(selected);

      details[dim] = DimensionRecommendDetail(
        dimension: dim,
        score: dimensionScores[dim] ?? 1.0,
        weight: weights[dim] ?? 0,
        allocated: needed,
        selected: selected.length,
        difficultyRange: range,
        sections: sections,
      );
    }

    // 如果题目不够，补充综合题
    if (recommended.length < targetCount) {
      final int deficit = targetCount - recommended.length;
      final List<LibraryQuestion> extra = await _fetchExtraCandidates(
        count: deficit,
        excludeIds: _shownIds,
      );
      for (final LibraryQuestion q in extra) {
        _shownIds.add(q.id);
      }
      recommended.addAll(extra);
    }

    // 随机打乱题目顺序
    recommended.shuffle(Random(DateTime.now().millisecondsSinceEpoch));

    return RecommendationResult(
      questions: recommended,
      details: details,
      profile: profile,
    );
  }

  /// 步骤1：计算权重 —— 弱项权重大、强项权重小
  Map<String, double> _calculateWeights(Map<String, double> scores) {
    // 逆序：分越低 → 权重越高
    final double total = scores.values.fold(0.0, (sum, s) => sum + (6.0 - s));
    final Map<String, double> weights = <String, double>{};
    for (final String dim in scores.keys) {
      final double s = scores[dim] ?? 1.0;
      weights[dim] = (6.0 - s) / total;
    }
    return weights;
  }

  /// 步骤2：按权重分配题目数
  Map<String, int> _allocateQuestions(
      Map<String, double> weights, int targetCount) {
    final Map<String, int> alloc = <String, int>{};

    // 每个维度至少 1 题
    int remaining = targetCount;
    for (final String dim in weights.keys) {
      alloc[dim] = 1;
      remaining--;
    }

    // 剩余题目按权重分配
    if (remaining > 0) {
      // 按权重从高到低排序
      final List<String> sorted = weights.keys.toList()
        ..sort((a, b) => weights[b]!.compareTo(weights[a]!));

      for (final String dim in sorted) {
        final int extra = (weights[dim]! * remaining).round();
        alloc[dim] = (alloc[dim] ?? 1) + extra;
      }

      // 修正总数偏差
      int currentTotal = alloc.values.fold(0, (a, b) => a + b);
      int idx = 0;
      while (currentTotal < targetCount && idx < sorted.length) {
        alloc[sorted[idx % sorted.length]] =
            (alloc[sorted[idx % sorted.length]] ?? 0) + 1;
        currentTotal++;
        idx++;
      }
      while (currentTotal > targetCount && idx < sorted.length) {
        final String dim = sorted[sorted.length - 1 - (idx % sorted.length)];
        if ((alloc[dim] ?? 0) > 1) {
          alloc[dim] = (alloc[dim] ?? 1) - 1;
          currentTotal--;
        }
        idx++;
      }
    }

    return alloc;
  }

  /// 步骤3：计算每个维度的目标难度区间
  ///
  /// 能力分 (1~5) → 服务器难度 (0~1) 的关系：
  /// - 弱项 (分低)：推荐简单题 → 难度 0.15~0.35
  /// - 中等：推荐中等题 → 难度 0.30~0.55
  /// - 强项 (分高)：推荐难题 → 难度 0.45~0.80
  Map<String, DifficultyRange> _calculateDifficultyRanges(
      Map<String, double> scores) {
    final Map<String, DifficultyRange> ranges = <String, DifficultyRange>{};
    for (final String dim in scores.keys) {
      final double s = scores[dim] ?? 3.0;
      // 用户能力分 → 目标服务器难度中心值
      // s=1.0 → center=0.25, s=3.0 → center=0.45, s=5.0 → center=0.65
      final double center = 0.15 + (s - 1.0) * 0.125;
      // 区间半宽：弱项更窄（精确匹配），强项更宽（接受范围大）
      final double halfWidth = 0.12 + (s - 1.0) * 0.02;
      ranges[dim] = DifficultyRange(
        min: (center - halfWidth).clamp(0.05, 0.9),
        max: (center + halfWidth).clamp(0.1, 0.95),
      );
    }
    return ranges;
  }

  /// 步骤4a：从服务器获取候选人题目
  Future<List<LibraryQuestion>> _fetchCandidates({
    required List<String> sections,
    required DifficultyRange difficultyRange,
    required Set<String> excludeIds,
  }) async {
    final List<LibraryQuestion> all = <LibraryQuestion>[];
    for (final String section in sections) {
      try {
        final List<LibraryQuestion> items = await fetchBySection(section);
        all.addAll(items);
      } catch (_) {}
    }

    // 客户端过滤：难度 + 排除已展示
    return all.where((q) {
      if (excludeIds.contains(q.id)) return false;
      return q.difficulty >= difficultyRange.min &&
          q.difficulty <= difficultyRange.max;
    }).toList();
  }

  /// 步骤4b：补充题目（不足时随机补）
  Future<List<LibraryQuestion>> _fetchExtraCandidates({
    required int count,
    required Set<String> excludeIds,
  }) async {
    // 从已缓存的 section 中随机取
    final List<LibraryQuestion> pool = <LibraryQuestion>[];
    for (final List<LibraryQuestion> items in _cache.values) {
      for (final LibraryQuestion q in items) {
        if (!excludeIds.contains(q.id)) {
          pool.add(q);
        }
      }
    }
    pool.shuffle();
    return pool.take(count).toList();
  }
}

/// 推荐结果
class RecommendationResult {
  final List<LibraryQuestion> questions;
  final Map<String, DimensionRecommendDetail> details;
  final UserRadarProfile profile;

  const RecommendationResult({
    required this.questions,
    required this.details,
    required this.profile,
  });
}

/// 单个维度的推荐详情
class DimensionRecommendDetail {
  final String dimension;
  final double score;
  final double weight;
  final int allocated;
  final int selected;
  final DifficultyRange difficultyRange;
  final List<String> sections;

  const DimensionRecommendDetail({
    required this.dimension,
    required this.score,
    required this.weight,
    required this.allocated,
    required this.selected,
    required this.difficultyRange,
    required this.sections,
  });
}

class DifficultyRange {
  final double min;
  final double max;

  const DifficultyRange({required this.min, required this.max});
}
