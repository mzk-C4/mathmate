/// 视频资料库 - 存储BV号，自动生成播放URL
/// 按学段和知识点分类
library;

class VideoResource {
  final String title;       // 知识点标题
  final String grade;       // 学段：小学/初中/高中
  final String module;      // 模块：如"方程与不等式"、"函数"等
  final String bvId;        // B站视频BV号（如 BV1qE411H7Uv）
  final String uploader;    // UP主
  final String? coverUrl;   // B站视频封面（懒加载）

  const VideoResource({
    required this.title,
    required this.grade,
    required this.module,
    required this.bvId,
    required this.uploader,
    this.coverUrl,
  });

  /// 自动生成B站视频播放URL
  String get url => bvId.isEmpty
      ? ''
      : 'https://www.bilibili.com/video/$bvId/';
}

final List<VideoResource> allVideoResources = <VideoResource>[
  // ========== 初中数学 ==========
  // 数与式
  const VideoResource(
    title: '有理数合集',
    grade: '初中',
    module: '数与式',
    bvId: 'BV1qE411H7Uv',
    uploader: '一数',
  ),
  const VideoResource(
    title: '初一数学170讲',
    grade: '初中',
    module: '数与式',
    bvId: 'BV1eT411N7xP',
    uploader: '一点老师',
  ),

  // 方程与不等式
  const VideoResource(
    title: '一元二次方程与韦达定理',
    grade: '初中',
    module: '方程与不等式',
    bvId: 'BV1qE411H7Uv',
    uploader: '一数',
  ),
  const VideoResource(
    title: '方程系列',
    grade: '初中',
    module: '方程与不等式',
    bvId: 'BV1eT411N7xP',
    uploader: '一点老师',
  ),

  // 函数初步
  const VideoResource(
    title: '一次/二次/反比例函数合集',
    grade: '初中',
    module: '函数初步',
    bvId: 'BV1qE411H7Uv',
    uploader: '一数',
  ),
  const VideoResource(
    title: '函数系列',
    grade: '初中',
    module: '函数初步',
    bvId: 'BV1eT411N7xP',
    uploader: '一点老师',
  ),

  // 几何与图形
  const VideoResource(
    title: '全等/相似三角形合集 & 圆专题',
    grade: '初中',
    module: '几何与图形',
    bvId: 'BV1qE411H7Uv',
    uploader: '一数',
  ),
  const VideoResource(
    title: '几何辅助线技巧',
    grade: '初中',
    module: '几何与图形',
    bvId: 'BV1eT411N7xP',
    uploader: '一点老师',
  ),

  // 数据统计与概率
  const VideoResource(
    title: '数据分析与概率',
    grade: '初中',
    module: '数据统计与概率',
    bvId: 'BV1qE411H7Uv',
    uploader: '一数',
  ),

  // ========== 高中数学 ==========

  // ==================== 集合、逻辑与不等式 ====================
  const VideoResource(
    title: '集合与逻辑入门',
    grade: '高中',
    module: '集合、逻辑与不等式',
    bvId: 'BV1qE411H7Uv',
    uploader: '一数',
  ),
  const VideoResource(
    title: '不等式同步讲解',
    grade: '高中',
    module: '集合、逻辑与不等式',
    bvId: 'BV1oM4y117LP',
    uploader: '一数',
  ),
  const VideoResource(
    title: '核心概念梳理：集合与不等式',
    grade: '高中',
    module: '集合、逻辑与不等式',
    bvId: 'BV1Z5411j7jB',
    uploader: '王梦抒',
  ),
  const VideoResource(
    title: '集合+逻辑基础',
    grade: '高中',
    module: '集合、逻辑与不等式',
    bvId: 'BV1iZ4y1x7Zk',
    uploader: '铭哥套路高考数学',
  ),
  const VideoResource(
    title: '基本不等式技巧',
    grade: '高中',
    module: '集合、逻辑与不等式',
    bvId: 'BV1EP4y1R7fz',
    uploader: '云凌Sapphire',
  ),
  const VideoResource(
    title: '高考数学复习大全',
    grade: '高中',
    module: '集合、逻辑与不等式',
    bvId: 'BV1EJ411y7J6',
    uploader: '鲲哥带你学数学',
  ),

  // ==================== 函数体系（来自 curated 清单） ====================
  const VideoResource(
    title: '函数三要素：定义域、值域、解析式',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1v64y1v7kx',
    uploader: '一数',
  ),
  const VideoResource(
    title: '函数基本性质：单调、奇偶、周期、对称',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1SK411G72L',
    uploader: '一数',
  ),
  const VideoResource(
    title: '基本初等函数：一次/二次/指数/对数/幂/对勾',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1SK411G72L',
    uploader: '一数',
  ),
  const VideoResource(
    title: '函数图像与变换：平移、对称、翻折、伸缩',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1FU4y1x7Nq',
    uploader: '一数',
  ),
  const VideoResource(
    title: '函数与方程：零点存在、个数、图像法',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1ZEoSBkEtX',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '导数与应用：切线、单调、极值、最值、恒成立',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1sCQEB4E2R',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '切线放缩、同构、隐零点、极值点偏移',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1sCQEB4E2R',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '抽象函数：赋值法 + 性质综合 + 模型判断',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1i2pfzvEYM',
    uploader: '一数',
  ),
  const VideoResource(
    title: '函数不等式：构造、放缩、单调性脱f',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV13kdBBeEyo',
    uploader: '一数',
  ),
  const VideoResource(
    title: '高考高频结论速记：函数篇',
    grade: '高中',
    module: '函数体系',
    bvId: 'BV1Pe4y1R7Xh',
    uploader: '小姚老师',
  ),

  // ==================== 三角函数 ====================
  const VideoResource(
    title: '正弦/余弦定理',
    grade: '高中',
    module: '三角函数',
    bvId: 'BV1nL41187k7',
    uploader: '一数',
  ),
  const VideoResource(
    title: '三角函数母题精讲',
    grade: '高中',
    module: '三角函数',
    bvId: 'BV1hC4y1j7xK',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '恒等变换技巧',
    grade: '高中',
    module: '三角函数',
    bvId: 'BV1iZ4y1x7Zk',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '三角函数基础',
    grade: '高中',
    module: '三角函数',
    bvId: 'BV1Z5411j7jB',
    uploader: '王梦抒',
  ),
  const VideoResource(
    title: '诱导公式记忆法',
    grade: '高中',
    module: '三角函数',
    bvId: 'BV1rk4y1A7mV',
    uploader: '铭哥套路高考数学',
  ),

  // ==================== 向量与复数（平面向量 来自 curated 清单） ====================
  const VideoResource(
    title: '向量基本概念',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV16r4y1A7T6',
    uploader: '一数',
  ),
  const VideoResource(
    title: '平面向量基本定理',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1689TBWE87',
    uploader: '一数',
  ),
  const VideoResource(
    title: '坐标运算',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1XmXvBQETf',
    uploader: '一数',
  ),
  const VideoResource(
    title: '数量积：定义、坐标、运算律',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1qzX5BqE6J',
    uploader: '一数',
  ),
  const VideoResource(
    title: '极化恒等式',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1PA411N7dK',
    uploader: '一数',
  ),
  const VideoResource(
    title: '三角形四心向量表示',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1UW4y1h7u9',
    uploader: '一数',
  ),
  const VideoResource(
    title: '奔驰定理（含奔驰定理 + 四心）',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1S64y1y7Tb',
    uploader: '一数',
  ),
  const VideoResource(
    title: '基底法',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1UwDjBXEdn',
    uploader: '一数',
  ),
  const VideoResource(
    title: '几何意义法：投影、三角不等式',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1jhAKzTEDa',
    uploader: '一数',
  ),
  const VideoResource(
    title: '结论速解法：四心、奔驰、极化恒等式',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1S64y1y7Tb',
    uploader: '一数',
  ),
  const VideoResource(
    title: '复数专题',
    grade: '高中',
    module: '向量与复数',
    bvId: 'BV1jJ411274s',
    uploader: '佟大大还是ETT',
  ),

  // ==================== 立体几何（来自 curated 清单） ====================
  const VideoResource(
    title: '基本几何体与结构 + 斜二测',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1Gp4y1Q7K5',
    uploader: '一数',
  ),
  const VideoResource(
    title: '表面积与体积：公式 + 题型一步到位',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1Gp4y1Q7K5',
    uploader: '一数',
  ),
  const VideoResource(
    title: '点线面位置关系：公理、推论、异面、共面',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1X2dkBjENU',
    uploader: '一数',
  ),
  const VideoResource(
    title: '平行与垂直判定：线线↔线面↔面面',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1pF41137g2',
    uploader: '一数',
  ),
  const VideoResource(
    title: '空间角：异面角、线面角、二面角',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1LfDMBkEVB',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '空间距离：等体积法 + 向量法',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1sCQEB4E2R',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '外接球与内切球：墙角、直棱柱、正棱锥、对棱相等',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1nYozBpEFs',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '空间向量：建系、方向向量、法向量、求角求距',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1Mz421B7Pr',
    uploader: '一数',
  ),
  const VideoResource(
    title: '截面、翻折与轨迹：截面作图 + 翻折不变量',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV1GWGdztEXo',
    uploader: '一数',
  ),
  const VideoResource(
    title: '常见模型与结论：正四面体、三垂线、最小角定理',
    grade: '高中',
    module: '立体几何',
    bvId: 'BV19f4y117hk',
    uploader: '一数',
  ),

  // ==================== 解析几何（来自 curated 清单） ====================
  // 一、基础解题方法
  const VideoResource(
    title: '点差法：中点弦',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV183B1Y2E6H',
    uploader: '一数',
  ),
  const VideoResource(
    title: '平移齐次化：斜率和与积',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1DqzkBvE6T',
    uploader: '一数',
  ),
  const VideoResource(
    title: '仿射变换：椭圆变圆',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1DPmdYeE84',
    uploader: '一数',
  ),
  const VideoResource(
    title: '隐函数求导：切线速算',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1EWohB4ETE',
    uploader: '一数',
  ),
  const VideoResource(
    title: '非对称韦达定理',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1kaX5BGEok',
    uploader: '一数',
  ),
  const VideoResource(
    title: '极坐标与参数方程',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1U541167FQ',
    uploader: '一数',
  ),

  // 二、高阶几何模型
  const VideoResource(
    title: '蒙日圆',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV15LsnzcERh',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '阿基米德三角形',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1Tw4m1Z72q',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '阿波罗尼斯圆（阿氏圆）',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1RiULB9EpG',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '米勒圆：最大视角问题',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1uf4y1P7Ry',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '圆幂定理与根轴',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1Yv4y1N7p2',
    uploader: '小姚老师',
  ),

  // 三、圆锥曲线核心结论
  const VideoResource(
    title: '焦点三角形：面积与离心率',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1LSonBfEHs',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '焦半径公式：倾斜角+坐标法',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1m3F9zyEV1',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '抛物线焦点弦性质',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1Xn9SB8E8C',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '第三定义：斜率积为定值',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV16ZV1z7E5N',
    uploader: '赵礼显老师',
  ),
  const VideoResource(
    title: '圆锥曲线光学性质',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1qkAczWE5K',
    uploader: '赵礼显老师',
  ),

  // 四、直线与曲线综合
  const VideoResource(
    title: '联立+韦达定理：通法全解',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1ZY411s7xB',
    uploader: '一数',
  ),
  const VideoResource(
    title: '切线与切点弦',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1x3411Z7X6',
    uploader: '一数',
  ),
  const VideoResource(
    title: '定点定值问题',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1NeDrYtEQ3',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '弦长与面积最值',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1MH4y167ui',
    uploader: '小姚老师',
  ),

  // 五、轨迹方程求法
  const VideoResource(
    title: '轨迹方程：定义法、相关点法、参数法',
    grade: '高中',
    module: '解析几何',
    bvId: 'BV1JU4y1o7CF',
    uploader: '一数',
  ),

  // ==================== 数列 ====================
  const VideoResource(
    title: '等差与等比数列',
    grade: '高中',
    module: '数列',
    bvId: 'BV1nL41187k7',
    uploader: '一数',
  ),
  const VideoResource(
    title: '错位相减法',
    grade: '高中',
    module: '数列',
    bvId: 'BV1jJ411274s',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '零基础学数列',
    grade: '高中',
    module: '数列',
    bvId: 'BV1Z5411j7jB',
    uploader: '王梦抒',
  ),
  const VideoResource(
    title: '数列求通项公式',
    grade: '高中',
    module: '数列',
    bvId: 'BV1rk4y1A7mV',
    uploader: '铭哥套路高考数学',
  ),

  // ==================== 导数及其应用 ====================
  const VideoResource(
    title: '导数综合讲解',
    grade: '高中',
    module: '导数及其应用',
    bvId: 'BV1sCQEB4E2R',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '导数大题拆解',
    grade: '高中',
    module: '导数及其应用',
    bvId: 'BV1jJ411274s',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '极值点偏移专题',
    grade: '高中',
    module: '导数及其应用',
    bvId: 'BV1nL41187k7',
    uploader: '王梦抒',
  ),
  const VideoResource(
    title: '导数与不等式证明',
    grade: '高中',
    module: '导数及其应用',
    bvId: 'BV1iZ4y1x7Zk',
    uploader: '赵礼显老师',
  ),

  // ==================== 概率统计与排列组合 ====================
  const VideoResource(
    title: '排列组合合集',
    grade: '高中',
    module: '概率统计与排列组合',
    bvId: 'BV1nL41187k7',
    uploader: '一数',
  ),
  const VideoResource(
    title: '随机变量的期望方差',
    grade: '高中',
    module: '概率统计与排列组合',
    bvId: 'BV1jJ411274s',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '生活化案例讲解',
    grade: '高中',
    module: '概率统计与排列组合',
    bvId: 'BV1Z5411j7jB',
    uploader: '王梦抒',
  ),
  const VideoResource(
    title: '条件概率讲解',
    grade: '高中',
    module: '概率统计与排列组合',
    bvId: 'BV1iZ4y1x7Zk',
    uploader: '铭哥套路高考数学',
  ),

  // ==================== 思想方法（来自 curated 清单） ====================
  const VideoResource(
    title: '数形结合思想',
    grade: '高中',
    module: '思想方法',
    bvId: 'BV1Pe4y1R7Xh',
    uploader: '小姚老师',
  ),
  const VideoResource(
    title: '导数通法：切线、单调、极值、最值',
    grade: '高中',
    module: '思想方法',
    bvId: 'BV1sCQEB4E2R',
    uploader: '佟大大还是ETT',
  ),
  const VideoResource(
    title: '几何法：定理法、等体积法、补形法',
    grade: '高中',
    module: '思想方法',
    bvId: 'BV1pF41137g2',
    uploader: '一数',
  ),
  const VideoResource(
    title: '分类讨论思想',
    grade: '高中',
    module: '思想方法',
    bvId: 'BV1X2dkBjENU',
    uploader: '一数',
  ),
  const VideoResource(
    title: '立体几何解题流程',
    grade: '高中',
    module: '思想方法',
    bvId: 'BV19y4y1s7za',
    uploader: '一数',
  ),

  // ========== 大学数学 ==========

  // ==================== 高等数学 ====================
  const VideoResource(
    title: '极限',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV1D4DnYCEQS',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '一元微分',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV1zz4y1o7m2',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '一元积分',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV1ee411r71f',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '多元微分',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV16b421H7ac',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '重积分',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV11t42177s1',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '微分方程',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV1etZxBGEZc',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '无穷级数',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV13w4m1S7Rx',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '曲线曲面积分',
    grade: '大学',
    module: '高等数学',
    bvId: 'BV1Xy4y1L7Z5',
    uploader: '宋浩老师',
  ),

  // ==================== 线性代数 ====================
  const VideoResource(
    title: '行列式',
    grade: '大学',
    module: '线性代数',
    bvId: 'BV1eN411r7ku',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '矩阵',
    grade: '大学',
    module: '线性代数',
    bvId: 'BV1c2421P7g8',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '线性方程组',
    grade: '大学',
    module: '线性代数',
    bvId: 'BV1ZM4y1n7VH',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '特征值/特征向量',
    grade: '大学',
    module: '线性代数',
    bvId: 'BV1TH4y1L7PV',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '二次型',
    grade: '大学',
    module: '线性代数',
    bvId: 'BV1ZC411j7mu',
    uploader: '宋浩老师',
  ),

  // ==================== 概率论与数理统计 ====================
  const VideoResource(
    title: '概率',
    grade: '大学',
    module: '概率论与数理统计',
    bvId: 'BV1JXppejE8q',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '一维分布',
    grade: '大学',
    module: '概率论与数理统计',
    bvId: 'BV1T14y1h7uV',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '二维分布',
    grade: '大学',
    module: '概率论与数理统计',
    bvId: 'BV1xm9eY7E5y',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '参数估计',
    grade: '大学',
    module: '概率论与数理统计',
    bvId: 'BV1FbKBzzEP8',
    uploader: '宋浩老师',
  ),
  const VideoResource(
    title: '假设检验',
    grade: '大学',
    module: '概率论与数理统计',
    bvId: 'BV1yf4y1K7so',
    uploader: '宋浩老师',
  ),
];

/// 按学段获取视频资源
List<VideoResource> getVideoResourcesByGrade(String grade) {
  return allVideoResources
      .where((r) => r.grade == grade)
      .toList();
}

/// 按模块获取视频资源
List<VideoResource> getVideoResourcesByModule(String module) {
  return allVideoResources
      .where((r) => r.module == module)
      .toList();
}

/// 获取所有学段
List<String> getAllGrades() {
  return allVideoResources.map((r) => r.grade).toSet().toList();
}

/// 获取指定学段的所有模块
List<String> getModulesByGrade(String grade) {
  return allVideoResources
      .where((r) => r.grade == grade)
      .map((r) => r.module)
      .toSet()
      .toList();
}
