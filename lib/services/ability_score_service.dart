import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mathmate/models/user_radar_profile.dart';

/// 单个维度的答题统计
class DimensionStats {
  int totalQuestions; // N
  int correctQuestions; // 正确题数
  double avgDifficulty; // D (1~5)

  DimensionStats({
    this.totalQuestions = 0,
    this.correctQuestions = 0,
    this.avgDifficulty = 3.0,
  });

  double get correctRate =>
      totalQuestions > 0 ? correctQuestions / totalQuestions : 0.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'totalQuestions': totalQuestions,
        'correctQuestions': correctQuestions,
        'avgDifficulty': avgDifficulty,
      };

  factory DimensionStats.fromJson(Map<String, dynamic> json) =>
      DimensionStats(
        totalQuestions: (json['totalQuestions'] as num?)?.toInt() ?? 0,
        correctQuestions: (json['correctQuestions'] as num?)?.toInt() ?? 0,
        avgDifficulty:
            (json['avgDifficulty'] as num?)?.toDouble() ?? 3.0,
      );
}

/// 数学能力评分服务
///
/// 实现 plan.md 中的三阶算法：
/// 1. 贝叶斯收缩正确率（自评作为先验）
/// 2. 题量熟练度权重（对数增长）
/// 3. 难度系数修正
///
/// 结果范围：1.0 ~ 5.0
///
/// 支持两套维度体系（K-12 / 大学），按用户年级自动切换。
/// 两套体系的自评与答题统计分别存储，切换年级不会丢失数据。
class AbilityScoreService extends ChangeNotifier {
  static final AbilityScoreService _instance = AbilityScoreService._();
  factory AbilityScoreService() => _instance;
  AbilityScoreService._();

  /// 超参数
  static const double n0 = 5.0; // 初始虚拟样本量
  static const double lambda = 30.0; // 题量成长半衰期
  // [摆拍] static const double demoLambda = 15.0; // 摆拍模式温和成长半衰期（≈ +0.05/题）

  // [摆拍] 演示模式开关
  // bool _demoMode = false;
  // bool get demoMode => _demoMode;

  /// K-12 自评画像
  UserRadarProfile? _selfAssessmentK12;
  /// 大学自评画像
  UserRadarProfile? _selfAssessmentUni;

  /// K-12 各维度答题统计
  final List<DimensionStats> _statsK12 = List<DimensionStats>.generate(
    UserRadarProfile.k12DimensionNames.length,
    (_) => DimensionStats(),
  );
  /// 大学各维度答题统计
  final List<DimensionStats> _statsUni = List<DimensionStats>.generate(
    UserRadarProfile.universityDimensionNames.length,
    (_) => DimensionStats(),
  );

  /// 当前年级（由外部设置，默认 null=K-12 行为）
  int? _currentGrade;
  int? get currentGrade => _currentGrade;

  /// 根据当前年级取对应的自评画像
  UserRadarProfile? get selfAssessment =>
      UserRadarProfile.isUniversity(_currentGrade) ? _selfAssessmentUni : _selfAssessmentK12;

  /// 根据当前年级取对应的答题统计
  List<DimensionStats> get stats =>
      UserRadarProfile.isUniversity(_currentGrade) ? _statsUni : _statsK12;

  /// 当前维度名称列表
  List<String> get currentDimensionNames =>
      UserRadarProfile.dimensionNamesFor(_currentGrade);

  /// 是否已完成自评（当前维度体系）
  bool get hasAssessment => selfAssessment != null;

  /// 设置当前年级并重新通知监听者
  void setGrade(int? grade) {
    if (_currentGrade == grade) return;
    _currentGrade = grade;
    notifyListeners();
  }

  // [摆拍] 启用演示模式：自评全 3.0（显示 6.00 分），清空答题统计，快速成长 λ
  // Future<void> enableDemoMode() async {
  //   _demoMode = true;
  //   final List<double> scores = List<double>.filled(6, 3.0);
  //   await saveSelfAssessment(UserRadarProfile(scores: scores));
  //   final List<DimensionStats> active = stats;
  //   for (final DimensionStats s in active) {
  //     s.totalQuestions = 0;
  //     s.correctQuestions = 0;
  //     s.avgDifficulty = 3.0;
  //   }
  //   await _saveStats();
  //   notifyListeners();
  //   debugPrint('[AbilityScore] Demo mode ON — λ=$demoLambda, self=3.0, stats cleared');
  // }

  // [摆拍] 关闭演示模式
  // void disableDemoMode() {
  //   _demoMode = false;
  //   notifyListeners();
  //   debugPrint('[AbilityScore] Demo mode OFF');
  // }

  /// 保存自评分数（自动关联到对应维度体系）
  Future<void> saveSelfAssessment(UserRadarProfile profile) async {
    if (profile.dimensionSet == 'university') {
      _selfAssessmentUni = profile;
    } else {
      _selfAssessmentK12 = profile;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ability_self_assessment', jsonEncode(profile.toJson()));
    // 同时按维度体系分存一份，避免互相覆盖
    await prefs.setString(
      'ability_sa_${profile.dimensionSet}',
      jsonEncode(profile.toJson()),
    );
    notifyListeners();
  }

  /// 加载已保存的自评和答题统计
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // 加载 K-12 自评
    final String? rawK12 = prefs.getString('ability_sa_k12');
    if (rawK12 != null) {
      try {
        _selfAssessmentK12 = UserRadarProfile.fromJson(
          jsonDecode(rawK12) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    // 加载大学自评
    final String? rawUni = prefs.getString('ability_sa_university');
    if (rawUni != null) {
      try {
        _selfAssessmentUni = UserRadarProfile.fromJson(
          jsonDecode(rawUni) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    // 兼容旧版：没有按维度体系分存时，从公共 key 加载并推断
    if (_selfAssessmentK12 == null && _selfAssessmentUni == null) {
      final String? raw = prefs.getString('ability_self_assessment');
      if (raw != null) {
        try {
          final profile = UserRadarProfile.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          // 旧版没有 dimensionSet 字段，默认归入 K-12
          if (profile.dimensionSet == 'university') {
            _selfAssessmentUni = profile;
          } else {
            _selfAssessmentK12 = profile;
          }
        } catch (_) {}
      }
    }

    // 加载 K-12 答题统计
    final String? statsRawK12 = prefs.getString('ability_stats_k12');
    if (statsRawK12 != null) {
      _loadStatsInto(statsRawK12, _statsK12);
    } else {
      // 兼容旧版 key
      final String? statsRaw = prefs.getString('ability_stats');
      if (statsRaw != null) _loadStatsInto(statsRaw, _statsK12);
    }

    // 加载大学答题统计
    final String? statsRawUni = prefs.getString('ability_stats_university');
    if (statsRawUni != null) {
      _loadStatsInto(statsRawUni, _statsUni);
    }

    notifyListeners();
  }

  void _loadStatsInto(String raw, List<DimensionStats> target) {
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      for (int i = 0; i < list.length && i < target.length; i++) {
        target[i] = DimensionStats.fromJson(list[i] as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  /// 保存答题统计
  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'ability_stats_k12',
      jsonEncode(_statsK12.map((s) => s.toJson()).toList()),
    );
    await prefs.setString(
      'ability_stats_university',
      jsonEncode(_statsUni.map((s) => s.toJson()).toList()),
    );
  }

  /// 更新某维度的答题统计（供题库模块调用）
  ///
  /// [dimensionIndex] 在当前维度体系中的索引
  Future<void> recordAnswer({
    required int dimensionIndex,
    required bool isCorrect,
    double difficulty = 3.0,
  }) async {
    final List<DimensionStats> activeStats = stats;
    if (dimensionIndex < 0 || dimensionIndex >= activeStats.length) return;

    final DimensionStats s = activeStats[dimensionIndex];
    // 指数移动平均更新难度
    s.avgDifficulty = s.avgDifficulty * 0.9 + difficulty * 0.1;
    s.totalQuestions++;
    if (isCorrect) s.correctQuestions++;

    await _saveStats();
    notifyListeners();
  }

  /// 计算某个维度的最终能力分（核心算法）
  ///
  /// [dimensionIndex] 维度索引（0~5，对应当前维度体系的六个维度）。
  /// 所有维度统一使用标准三阶算法计算。
  ///
  /// 返回 1.0 ~ 5.0 的分数
  double calculateScore(int dimensionIndex) {
    final List<String> dimNames = currentDimensionNames;
    if (dimensionIndex < 0 || dimensionIndex >= dimNames.length) {
      return 1.0;
    }

    final UserRadarProfile? sa = selfAssessment;
    final List<DimensionStats> activeStats = stats;
    final double self = sa?.scores[dimensionIndex] ?? 1.0;
    final DimensionStats s = activeStats[dimensionIndex];
    final int N = s.totalQuestions;
    final double R = s.correctRate;
    final double D = s.avgDifficulty.clamp(1.0, 5.0);

    return _applyAlgorithm(
      self: self,
      N: N,
      R: R,
      D: D,
      lambdaValue: lambda,
      // [摆拍] lambdaValue: _demoMode ? demoLambda : lambda,
    );
  }

  /// 通用三阶算法
  ///
  /// [self] 自评 1~5, [N] 做题量, [R] 正确率 0~1, [D] 平均难度 1~5,
  /// [lambdaValue] 半衰期参数
  double _applyAlgorithm({
    required double self,
    required int N,
    required double R,
    required double D,
    required double lambdaValue,
  }) {
    // 第一步：贝叶斯收缩正确率
    final double selfRate = self / 5.0;
    final double adjustedRate =
        (N * R + n0 * selfRate) / (N + n0);

    // 第二步：题量熟练度权重
    final double weight = 1 - math.exp(-N / lambdaValue);

    // 第三步：融合基础分
    final double baseScore =
        (selfRate * (1 - weight) + adjustedRate * weight) * 5.0;

    // 第四步：难度修正
    final double difficultyFactor = 1 + (D - 3) / 10;
    final double finalScore = baseScore * difficultyFactor;

    // 边界保护
    return finalScore.clamp(1.0, 5.0);
  }

  /// 获取当前维度体系的所有维度计算分数
  UserRadarProfile get computedProfile {
    final List<String> dimNames = currentDimensionNames;
    final List<double> scores = <double>[];
    for (int i = 0; i < dimNames.length; i++) {
      scores.add(calculateScore(i));
    }
    return UserRadarProfile(
      scores: scores,
      dimensionSet: UserRadarProfile.dimensionSetFor(_currentGrade),
    );
  }

  /// 重置所有数据
  Future<void> reset() async {
    _selfAssessmentK12 = null;
    _selfAssessmentUni = null;
    for (final DimensionStats s in _statsK12) {
      s.totalQuestions = 0;
      s.correctQuestions = 0;
      s.avgDifficulty = 3.0;
    }
    for (final DimensionStats s in _statsUni) {
      s.totalQuestions = 0;
      s.correctQuestions = 0;
      s.avgDifficulty = 3.0;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ability_self_assessment');
    await prefs.remove('ability_sa_k12');
    await prefs.remove('ability_sa_university');
    await prefs.remove('ability_stats');
    await prefs.remove('ability_stats_k12');
    await prefs.remove('ability_stats_university');
    notifyListeners();
  }
}
