import 'package:flutter/material.dart';
import 'package:mathmate/models/user_radar_profile.dart';
import 'package:mathmate/pages/exam_taking_page.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/services/auth_service.dart';
import 'package:mathmate/services/exam_api.dart';

/// 自由组卷配置页 —— 选择维度、难度、题量后创建考试
class ExamCreationPage extends StatefulWidget {
  const ExamCreationPage({super.key});

  @override
  State<ExamCreationPage> createState() => _ExamCreationPageState();
}

class _ExamCreationPageState extends State<ExamCreationPage> {
  final AbilityScoreService _abilityService = AbilityScoreService();
  final ExamApi _api = ExamApi(baseUrl: ExamSystemConfig.baseUrl);

  /// 选中的维度（board），null 表示不限
  String? _selectedDimension;

  /// 题量
  int _questionCount = 5;

  /// 难度区间
  double _difficultyMin = 0.2;
  double _difficultyMax = 0.7;

  /// 题型选择
  bool _includeChoice = true;
  bool _includeBlank = true;
  bool _includeShortAnswer = false;

  /// 后端是否可用
  bool _serverAvailable = false;
  bool _checking = true;
  bool _starting = false;

  ColorScheme get cs => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final bool ok = await _api.healthCheck();
    if (mounted) {
      setState(() {
        _serverAvailable = ok;
        _checking = false;
      });
    }
  }

  /// 根据用户画像智能预设难度
  void _autoConfigFromProfile() {
    final UserRadarProfile profile = _abilityService.computedProfile;
    final double avgScore =
        profile.scores.reduce((a, b) => a + b) / profile.scores.length;
    // 能力分 1~5 → 服务器难度 0~1
    final double center = ((avgScore - 1.0) * 0.25 + 0.15).clamp(0.1, 0.85);
    setState(() {
      _difficultyMin = (center - 0.15).clamp(0.0, 0.9);
      _difficultyMax = (center + 0.15).clamp(0.1, 1.0);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已根据你的学习画像设置难度范围：'
          '${_difficultyMin.toStringAsFixed(2)} ~ ${_difficultyMax.toStringAsFixed(2)}',
        ),
      ),
    );
  }

  Future<void> _startExam() async {
    if (!_serverAvailable) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('考试服务不可用，请检查后端是否启动')));
      return;
    }

    final String? studentId = AuthService().user?.id.trim();
    if (studentId == null || studentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录状态异常，请退出账号后重新登录')),
      );
      return;
    }

    final List<String> questionTypes = _buildQuestionTypes();
    final List<String>? boards = _boardsForSelectedDimension();
    setState(() => _starting = true);
    try {
      final int available = await _api.availableQuestionCount(
        boards: boards,
        difficultyMin: _difficultyMin,
        difficultyMax: _difficultyMax,
        questionTypes: questionTypes,
      );
      if (!mounted) return;
      if (available <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前条件下没有可用题目，请调整板块、难度或题型')),
        );
        return;
      }

      final int actualCount = _questionCount > available
          ? available
          : _questionCount;
      if (actualCount < _questionCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前条件仅有 $available 道题，将按 $actualCount 道组卷')),
        );
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExamTakingPage(
            api: _api,
            studentId: studentId,
            title: _selectedDimension != null
                ? '${_selectedDimension!}专项测试'
                : '自由组卷测试',
            totalCount: actualCount,
            boards: boards,
            difficultyMin: _difficultyMin,
            difficultyMax: _difficultyMax,
            questionTypes: questionTypes,
          ),
        ),
      );
    } on ExamApiException catch (e) {
      if (!mounted) return;
      final message = e.statusCode == 401
          ? '登录已过期，请退出账号后重新登录'
          : '组卷服务请求失败：${e.message}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('获取可用题量失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  List<String>? _boardsForSelectedDimension() {
    final String? dimension = _selectedDimension;
    if (dimension == null) return null;
    return UserRadarProfile.dimensionTagsFor(
      _abilityService.currentGrade,
    )[dimension];
  }

  List<String> _buildQuestionTypes() {
    final List<String> types = <String>[];
    if (_includeChoice) types.add('choice');
    if (_includeBlank) types.add('blank');
    if (_includeShortAnswer) types.add('short_answer');
    return types;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(title: const Text('自由组卷'), backgroundColor: cs.surface),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 服务状态
              _buildServerStatus(),
              const SizedBox(height: 20),

              // 智能推荐按钮
              _buildProfileHint(),
              const SizedBox(height: 20),

              // 维度选择
              _buildSectionTitle('选择练习维度'),
              const SizedBox(height: 10),
              _buildDimensionGrid(),
              const SizedBox(height: 20),

              // 题量
              _buildSectionTitle('题目数量：$_questionCount'),
              const SizedBox(height: 6),
              Slider(
                value: _questionCount.toDouble(),
                min: 5,
                max: 30,
                divisions: 5,
                label: '$_questionCount',
                onChanged: (v) => setState(() => _questionCount = v.round()),
              ),
              const SizedBox(height: 16),

              // 难度区间
              Row(
                children: <Widget>[
                  Expanded(child: _buildSectionTitle('难度区间')),
                  TextButton.icon(
                    onPressed: _autoConfigFromProfile,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                    label: const Text('智能推荐'),
                    style: TextButton.styleFrom(foregroundColor: cs.primary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              RangeSlider(
                values: RangeValues(_difficultyMin, _difficultyMax),
                min: 0.0,
                max: 1.0,
                divisions: 20,
                labels: RangeLabels(
                  _difficultyMin.toStringAsFixed(2),
                  _difficultyMax.toStringAsFixed(2),
                ),
                onChanged: (v) => setState(() {
                  _difficultyMin = v.start;
                  _difficultyMax = v.end;
                }),
              ),
              const SizedBox(height: 16),

              // 题型选择
              _buildSectionTitle('包含题型'),
              const SizedBox(height: 10),
              _buildTypeCheckboxes(),
              const SizedBox(height: 32),

              // 开始考试按钮
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed:
                      !_starting &&
                          (_includeChoice ||
                              _includeBlank ||
                              _includeShortAnswer)
                      ? _startExam
                      : null,
                  icon: const Icon(Icons.assignment_rounded),
                  label: Text(
                    _starting ? '正在检查题量...' : '开始考试',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerStatus() {
    if (_checking) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('正在连接考试服务...', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Icon(
          _serverAvailable ? Icons.check_circle : Icons.error_outline,
          color: _serverAvailable ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          _serverAvailable ? '考试服务已连接' : '考试服务未连接（请启动后端）',
          style: TextStyle(
            color: _serverAvailable ? Colors.green : Colors.red,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHint() {
    final UserRadarProfile profile = _abilityService.computedProfile;
    final double avgScore =
        profile.scores.reduce((a, b) => a + b) / profile.scores.length;
    // 找最弱维度
    int weakestIdx = 0;
    for (int i = 1; i < profile.scores.length; i++) {
      if (profile.scores[i] < profile.scores[weakestIdx]) weakestIdx = i;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.tips_and_updates_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '综合能力 ${(avgScore * UserRadarProfile.displayMultiplier).toStringAsFixed(1)} 分 | '
              '建议加强「${profile.names[weakestIdx]}」',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          OutlinedButton(
            onPressed: _autoConfigFromProfile,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('应用', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildDimensionGrid() {
    final List<String> dims = _abilityService.currentDimensionNames;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        // "不限"选项
        ChoiceChip(
          label: const Text('不限'),
          selected: _selectedDimension == null,
          onSelected: (_) => setState(() => _selectedDimension = null),
        ),
        ...dims.map((dim) {
          return ChoiceChip(
            label: Text(dim),
            selected: _selectedDimension == dim,
            onSelected: (sel) {
              setState(() => _selectedDimension = sel ? dim : null);
            },
          );
        }),
      ],
    );
  }

  Widget _buildTypeCheckboxes() {
    return Row(
      children: <Widget>[
        FilterChip(
          label: const Text('选择题'),
          selected: _includeChoice,
          onSelected: (v) {
            if (_includeChoice || _includeBlank || _includeShortAnswer || v) {
              setState(() => _includeChoice = v);
            }
          },
        ),
        const SizedBox(width: 10),
        FilterChip(
          label: const Text('填空题'),
          selected: _includeBlank,
          onSelected: (v) {
            if (_includeChoice || _includeBlank || _includeShortAnswer || v) {
              setState(() => _includeBlank = v);
            }
          },
        ),
        const SizedBox(width: 10),
        FilterChip(
          label: const Text('简答题'),
          selected: _includeShortAnswer,
          onSelected: (v) {
            if (_includeChoice || _includeBlank || _includeShortAnswer || v) {
              setState(() => _includeShortAnswer = v);
            }
          },
        ),
      ],
    );
  }
}
