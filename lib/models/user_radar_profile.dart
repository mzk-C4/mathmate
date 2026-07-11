/// 用户六维数学能力画像数据模型
///
/// 内部存储 1.0~5.0 分，展示时 ×2 映射为 10 分制。
///
/// 支持两套维度体系：
/// - K-12（grade 1~12）：基础代数工具、函数微积分、数列三角、平面与空间几何、概率统计、组合计数
/// - 大学（grade ≥13）：线性代数、概率论、高等数学、离散数学、数学建模、数值计算
///
/// 通过 [dimensionSet] 字段区分，[names] 实例字段携带当前画像的维度名称列表。
class UserRadarProfile {
  // ---------------------------------------------------------------------------
  // K-12 维度体系（小学/初中/高中）
  // ---------------------------------------------------------------------------

  static const List<String> k12DimensionNames = [
    '基础代数工具',
    '函数微积分',
    '数列三角',
    '平面与空间几何',
    '概率统计',
    '组合计数',
  ];

  static const Map<String, List<String>> k12DimensionTags = <String, List<String>>{
    '基础代数工具': <String>['集合与逻辑', '复数', '不等式'],
    '函数微积分': <String>['函数与导数'],
    '数列三角': <String>['数列', '三角函数'],
    '平面与空间几何': <String>['向量', '立体几何', '解析几何'],
    '概率统计': <String>['概率统计'],
    '组合计数': <String>['计数原理'],
  };

  // ---------------------------------------------------------------------------
  // 大学维度体系（grade ≥ 13）
  // 题库标签复用现有 K-12 section 做近似映射，后续可追加大学专属题目
  // ---------------------------------------------------------------------------

  static const List<String> universityDimensionNames = [
    '线性代数',
    '概率论',
    '高等数学',
    '离散数学',
    '数学建模',
    '数值计算',
  ];

  static const Map<String, List<String>> universityDimensionTags = <String, List<String>>{
    '线性代数': <String>['复数', '向量'],
    '概率论': <String>['概率统计'],
    '高等数学': <String>['函数与导数', '不等式'],
    '离散数学': <String>['集合与逻辑', '计数原理'],
    '数学建模': <String>['解析几何', '函数与导数'],
    '数值计算': <String>['数列', '不等式'],
  };

  // ---------------------------------------------------------------------------
  // 年级感知静态方法
  // ---------------------------------------------------------------------------

  /// 根据年级获取对应的维度名称列表
  static List<String> dimensionNamesFor(int? grade) =>
      (grade != null && grade >= 13) ? universityDimensionNames : k12DimensionNames;

  /// 根据年级获取对应的维度→题库标签映射
  static Map<String, List<String>> dimensionTagsFor(int? grade) =>
      (grade != null && grade >= 13) ? universityDimensionTags : k12DimensionTags;

  /// 是否为大学维度
  static bool isUniversity(int? grade) => grade != null && grade >= 13;

  /// 维度集合标识
  static String dimensionSetFor(int? grade) => isUniversity(grade) ? 'university' : 'k12';

  // ---------------------------------------------------------------------------
  // 向后兼容的静态 getter（默认 K-12，旧代码不传 grade 时使用）
  // ---------------------------------------------------------------------------

  static List<String> get dimensionNames => k12DimensionNames;
  static Map<String, List<String>> get dimensionTags => k12DimensionTags;

  // ---------------------------------------------------------------------------
  // 通用常量
  // ---------------------------------------------------------------------------

  /// 内部满分值
  static const double maxScore = 5.0;

  /// 展示倍率（内部分数 × displayMultiplier = 展示分）
  static const double displayMultiplier = 2.0;

  /// 展示满分值
  static const double displayMaxScore = maxScore * displayMultiplier; // 10.0

  // ---------------------------------------------------------------------------
  // 实例字段
  // ---------------------------------------------------------------------------

  /// 维度集合：'k12' 或 'university'
  final String dimensionSet;

  /// 当前画像的维度名称列表
  final List<String> names;

  /// 各维度得分（1.0 ~ 5.0），与 [names] 一一对应
  final List<double> scores;

  UserRadarProfile({
    List<double>? scores,
    String? dimensionSet,
  }) : dimensionSet = dimensionSet ?? 'k12',
       names = (dimensionSet == 'university') ? universityDimensionNames : k12DimensionNames,
       scores = scores ?? List<double>.filled(
         (dimensionSet == 'university') ? universityDimensionNames.length : k12DimensionNames.length,
         1.0,
       );

  /// 从年级创建空白画像
  factory UserRadarProfile.emptyFor(int? grade) {
    final String ds = dimensionSetFor(grade);
    return UserRadarProfile(dimensionSet: ds);
  }

  /// 从 JSON 反序列化
  factory UserRadarProfile.fromJson(Map<String, dynamic> json) {
    final String ds = ((json['dimensionSet'] as String?)?.trim() ?? '').toLowerCase();
    final String dimensionSet = (ds == 'university' || ds == 'uni')
        ? 'university'
        : 'k12';
    final List<String> dimNames = dimensionSet == 'university'
        ? universityDimensionNames
        : k12DimensionNames;

    final List<double> scores = <double>[];
    for (final String name in dimNames) {
      scores.add(((json[name] as num?)?.toDouble() ?? 1.0).clamp(1.0, maxScore));
    }
    return UserRadarProfile(scores: scores, dimensionSet: dimensionSet);
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'dimensionSet': dimensionSet,
    };
    for (int i = 0; i < names.length; i++) {
      json[names[i]] = scores[i];
    }
    return json;
  }

  /// 获取指定维度的得分
  double getScore(String dimension) {
    final int index = names.indexOf(dimension);
    return index >= 0 ? scores[index] : 1.0;
  }

  /// 获取维度名→得分的映射
  Map<String, double> get scoreMap {
    final Map<String, double> map = <String, double>{};
    for (int i = 0; i < names.length; i++) {
      map[names[i]] = scores[i];
    }
    return map;
  }
}
