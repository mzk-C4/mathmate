import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mathmate/beautiful_result_page.dart';
import 'package:mathmate/pages/chat_home_page.dart';
import 'package:mathmate/notes_page.dart';
import 'package:mathmate/geogebra_page.dart';
import 'package:mathmate/data/conversation_repository.dart';
import 'package:mathmate/data/hive_models.dart';
import 'package:mathmate/data/history_repository.dart';
import 'package:mathmate/data/video_resources.dart';
import 'package:mathmate/grade_selection_page.dart';
import 'package:mathmate/history_list_page.dart';
import 'package:mathmate/pages/video_player_page.dart';
import 'package:mathmate/profile_page.dart';
import 'package:mathmate/scanner/enhanced_crop_page.dart';
import 'package:mathmate/services/scanner_service.dart';
import 'package:mathmate/services/theme_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mathmate/services/video_recommendation_service.dart';
import 'package:mathmate/theme/app_theme.dart';
import 'package:mathmate/responsive/responsive_shell.dart';
import 'package:mathmate/tutorial_page.dart';
import 'package:mathmate/services/update_service.dart';
import 'package:mathmate/pages/geogebra_chat_entry.dart';
import 'package:mathmate/agents/orchestrator.dart';
import 'package:mathmate/agents/visualizer_agent.dart';
import 'package:mathmate/library/services/material_repository.dart';
import 'package:mathmate/exam/pages/question_bank_page.dart';
import 'package:mathmate/pages/ability_assessment_page.dart';
import 'package:mathmate/pages/practice_page.dart';
import 'package:mathmate/services/ability_score_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await dotenv.load(fileName: ".env");
  }

  // 初始化设备ID
  final prefs = await SharedPreferences.getInstance();
  if (!prefs.containsKey('device_id')) {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    String deviceId = '';
    if (deviceInfo is AndroidDeviceInfo) {
      deviceId = deviceInfo.id;
    } else if (deviceInfo is IosDeviceInfo) {
      deviceId = deviceInfo.identifierForVendor ?? '';
    } else if (kIsWeb) {
      deviceId = 'web-${DateTime.now().millisecondsSinceEpoch}';
    }
    await prefs.setString('device_id', deviceId);
  }

  if (kIsWeb) {
    // Web: 跳过 Isar 初始化
  } else {
    await HistoryRepository.instance.init();
    await ConversationRepository.instance.init();
  }
  await ThemeService.instance.init();
  await MaterialRepository.instance.init();
  await AbilityScoreService().load();

  // 多智能体注册（软件杯参赛：多智能体协同架构）
  Orchestrator.instance.register(VisualizerAgent());

  final bool isFirst;
  if (kIsWeb) {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    isFirst = !prefs.containsKey('web_grade');
  } else {
    isFirst = await HistoryRepository.instance.isFirstLaunch();
  }
  // Web 端跳过教程（避免选完年级又卡教程页）
  final bool tutorialCompleted = kIsWeb ? true : await HistoryRepository.instance.isTutorialCompleted();
  // 已有年级但未完成能力自评的用户，引导至自评页
  final bool needsAssessment = !isFirst && !AbilityScoreService().hasAssessment;
  runApp(MathMateApp(
    checkFirstLaunch: isFirst,
    showTutorial: !tutorialCompleted && !isFirst && !needsAssessment,
    showAssessment: needsAssessment,
  ));
}

class MathMateApp extends StatefulWidget {
  final bool checkFirstLaunch;
  final bool showTutorial;
  final bool showAssessment;

  const MathMateApp({
    super.key,
    required this.checkFirstLaunch,
    this.showTutorial = false,
    this.showAssessment = false,
  });

  @override
  State<MathMateApp> createState() => _MathMateAppState();
}

class _MathMateAppState extends State<MathMateApp> {
  late ThemeService _themeService;

  @override
  void initState() {
    super.initState();
    _themeService = ThemeService.instance;
    _themeService.addListener(_onThemeChanged);
    // 启动 3 秒后静默检查更新
    Future.delayed(const Duration(seconds: 3), _checkAutoUpdate);
  }

  Future<void> _checkAutoUpdate() async {
    final update = await UpdateService.checkUpdate();
    if (!mounted || update == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('最新版本: ${update.version}\n\n${update.releaseNotes}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final msg = await UpdateService.downloadAndInstall(update);
              if (msg != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  ThemeMode get _themeMode {
    switch (_themeService.mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        quill.FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: _getInitialPage(),
    );
  }

  Widget _getInitialPage() {
    if (widget.checkFirstLaunch) return const GradeSelectionPage();
    if (widget.showAssessment) {
      // 已有年级但未完成能力自评 → 引导自评后进入主页
      return AbilityAssessmentPage(nextPage: const MainScreen());
    }
    if (widget.showTutorial) return const TutorialPage();
    return const MainScreen();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  /// 用于通知 ProfilePage 的雷达图触发计数器（每次点击"我的"Tab 递增）
  final ValueNotifier<int> _radarTrigger = ValueNotifier<int>(0);
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      const QuestionHomePage(),
      const LibraryPage(),
      const NotesPage(),
      const PracticePage(),
      ProfilePage(radarTrigger: _radarTrigger),
    ];
  }

  @override
  void dispose() {
    _radarTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端导航壳：宽屏自动切换为 NavigationRail，窄屏保持原底部导航外观。
    return ResponsiveShell(
      currentIndex: _currentIndex,
      onTap: (int index) {
        setState(() => _currentIndex = index);
        // 每次点击"我的"Tab 都触发雷达图动画（包括重复点击）
        if (index == 3) {
          _radarTrigger.value++;
        }
      },
      pages: _pages,
      tabs: const <NavTab>[
        NavTab(icon: Icons.grid_view_rounded, label: '题目'),
        NavTab(icon: Icons.folder_special_rounded, label: '资料库'),
        NavTab(icon: Icons.bookmark_border_rounded, label: '笔记'),
        NavTab(icon: Icons.fitness_center_rounded, label: '练习'),
        NavTab(icon: Icons.account_circle_outlined, label: '我的'),
      ],
    );
  }
}

class QuestionHomePage extends StatefulWidget {
  const QuestionHomePage({super.key});

  @override
  State<QuestionHomePage> createState() => _QuestionHomePageState();
}

class _QuestionHomePageState extends State<QuestionHomePage> {
  ColorScheme get cs => Theme.of(context).colorScheme;

  final ScannerService _scannerService = ScannerService();
  final VideoRecommendationService _recommendationService = VideoRecommendationService();
  final TextEditingController _searchController = TextEditingController();

  bool _isScanning = false;
  bool _isRefreshing = false;
  List<VideoResource> _recommendedVideos = <VideoResource>[];
  String _currentGrade = '高中';

  @override
  void initState() {
    super.initState();
    _loadGradeLevelAndVideos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openSearchChat() {
    final String query = _searchController.text.trim();
    Navigator.of(context).push(_ChatTransitionRoute(
      targetPage: ChatHomePage(initialQuery: query.isNotEmpty ? query : null),
    ));
  }

  Future<void> _loadGradeLevelAndVideos() async {
    final int? grade = await HistoryRepository.instance.getGradeLevel();
    _currentGrade = grade != null
        ? (grade >= 1 && grade <= 6 ? '小学' : grade >= 7 && grade <= 9 ? '初中' : grade >= 10 && grade <= 12 ? '高中' : '大学')
        : '高中';

    // 优先使用AI推荐
    List<VideoResource> videos = await _recommendationService.recommendVideos();

    // AI推荐失败或返回空时，回退到本地筛选
    if (videos.isEmpty) {
      videos = getVideoResourcesByGrade(_currentGrade);
      try {
        final List<MathHistory> histories = await HistoryRepository.instance
            .watchHistories()
            .first
            .timeout(const Duration(seconds: 3));
        if (histories.isNotEmpty) {
          videos = _boostByHistory(videos, histories);
        }
      } catch (_) {}
      videos = List<VideoResource>.from(videos)..shuffle(Random());
    }

    if (mounted) {
      setState(() => _recommendedVideos = videos);
    }
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    await _loadGradeLevelAndVideos();
    if (mounted) setState(() => _isRefreshing = false);
  }

  List<VideoResource> _boostByHistory(
      List<VideoResource> videos, List<MathHistory> histories) {
    const List<String> keywords = <String>[
      '函数', '几何', '向量', '数列', '导数', '三角', '概率', '集合',
      '不等式', '解析几何', '立体几何', '方程', '统计', '排列', '组合',
    ];

    final Set<String> matchedModules = <String>{};
    for (final MathHistory h in histories.take(10)) {
      final String content = h.ocrContent;
      for (final String kw in keywords) {
        if (content.contains(kw)) {
          for (final VideoResource v in videos) {
            if (v.module.contains(kw) || v.title.contains(kw)) {
              matchedModules.add(v.module);
            }
          }
        }
      }
    }

    if (matchedModules.isEmpty) return videos;

    final List<VideoResource> boosted = videos
        .where((v) => matchedModules.contains(v.module))
        .toList();
    final List<VideoResource> rest = videos
        .where((v) => !matchedModules.contains(v.module))
        .toList();
    return <VideoResource>[...boosted, ...rest];
  }

  Future<void> _scanAndOpenResult() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
    });

    try {
      // 1. scanner_service 返回 XFile（Web 为内存 blob，原生为缓存文件）
      final XFile? scanned = await _scannerService.startScanning(context);

      if (!mounted) return;
      if (scanned == null) return; // 用户取消了

      // 2. 进入裁剪页面，返回裁剪后的 XFile
      final XFile? croppedFile = await Navigator.of(context).push<XFile>(
        MaterialPageRoute(
          builder: (_) => EnhancedCropPage(imageFile: scanned),
        ),
      );

      if (!mounted) return;
      if (croppedFile == null) return;

      // 3. 进入结果页面
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BeautifulResultPage(image: croppedFile),
        ),
      );
    } catch (e) {
      debugPrint('扫描流程异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照/选图失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 700;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Image.asset('assets/images/background.png', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: ColoredBox(color: cs.surface.withValues(alpha: 0.55)),
          ),
          SafeArea(
            child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 1100 : double.infinity),
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: cs.primary,
              backgroundColor: cs.surface,
              displacement: 40.0,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 12, isWide ? 24 : 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildSearchBar(),
                    const SizedBox(height: 14),
                    _buildProfileEntry(),
                    const SizedBox(height: 12),
                    _buildQuestionBankEntry(),
                    const SizedBox(height: 18),
                    _buildCameraHero(),
                    const SizedBox(height: 16),
                    _buildGeoChatCard(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text(
                          '数学视频推荐',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_isRefreshing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildVideoList(),
                    const SizedBox(height: 16),
                    _buildToolboxCard(),
                  ],
            ),
          ),
        ),
      ),
      ),
      ),
        ],
      ),
    );
  }

  /// 学习画像入口（软件杯：对话式学习画像）
  Widget _buildProfileEntry() {
    return FutureBuilder<LearnerProfile?>(
      future: ProfileRepository.instance.load(),
      builder: (BuildContext context, AsyncSnapshot<LearnerProfile?> snapshot) {
        final LearnerProfile? profile = snapshot.data;
        final bool ready = profile != null && profile.isUsable;
        final Color main = ready ? Colors.green : Colors.orange;
        return GestureDetector(
          onTap: () async {
            await ProfileSetupDialog.show(context);
            if (mounted) setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: ready ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: main.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  ready ? Icons.person_rounded : Icons.person_add_alt_rounded,
                  color: main,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        ready ? '学习画像已就绪' : '构建你的学习画像',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        ready
                            ? '完整度 ${(profile.completeness * 100).round()}% · 点击查看 / 随学随新'
                            : 'AI 对话抽取 6 维特征，开启个性化学习',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 题库入口卡（考试模块入口，接云端 API）
  Widget _buildQuestionBankEntry() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuestionBankPage()),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF5B6CFF), Color(0xFF4C6FFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('数学题库',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  SizedBox(height: 4),
                  Text('按板块/难度筛选 · 真题+解析 · 云端共享',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(_ChatTransitionRoute(
          targetPage: const ChatHomePage(),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.primary.withValues(alpha: 0.25), width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_awesome, color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '问任何数学问题，或点击开始对话...',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '问 AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraHero() {
    // Web 端无相机，改为上传图片入口
    if (kIsWeb) return _buildUploadHero();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          const Text(
            '拍一下，难题秒解决',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3F51B5),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CustomPaint(
                  size: const Size(double.infinity, 180),
                  painter: _FunctionWavePainter(),
                ),
                GestureDetector(
                  onTap: _scanAndOpenResult,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFF4C6FFF), Color(0xFF3557E5)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(
                            0xFF4C6FFF,
                          ).withValues(alpha: 0.35),
                          blurRadius: 26,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isScanning
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Web 端上传图片入口（无相机，改为选图上传）。
  Widget _buildUploadHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_upload_rounded, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(
            '上传题目图片',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            '支持 JPG / PNG，AI 自动识别并解题',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _scanAndOpenResult,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('选择图片'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// GeoChat 智能几何助手入口卡片
  Widget _buildGeoChatCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const GeogebraChatPage(),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF6A5BFF), Color(0xFF4C6FFF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF4C6FFF).withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const <Widget>[
                  Text(
                    'GeoChat 智能几何助手',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '用自然语言对话，自动绘制 GeoGebra 图形',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolboxCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.work_outline_rounded, color: Color(0xFF3F51B5)),
              SizedBox(width: 10),
              Text(
                '数学工具箱',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 900 ? 4 : 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.0,
            ),
            itemCount: 6,
            itemBuilder: (BuildContext context, int index) {
              final List<Map<String, dynamic>> tools = <Map<String, dynamic>>[
                <String, dynamic>{
                  'icon': Icons.science_outlined,
                  'name': '科学计算器',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraPage(appName: 'scientific'),
                      ),
                    );
                  },
                },
                <String, dynamic>{
                  'icon': Icons.show_chart,
                  'name': '几何画板',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraPage(appName: 'geometry'),
                      ),
                    );
                  },
                },
                <String, dynamic>{
                  'icon': Icons.functions_outlined,
                  'name': '函数绘图',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraPage(
                          appName: 'graphing',
                        ),
                      ),
                    );
                  },
                },
                <String, dynamic>{
                  'icon': Icons.view_in_ar,
                  'name': '3D视图',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraPage(appName: '3d'),
                      ),
                    );
                  },
                },
                <String, dynamic>{
                  'icon': Icons.draw_outlined,
                  'name': '尺规作图',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraPage(appName: 'notes'),
                      ),
                    );
                  },
                },
                <String, dynamic>{
                  'icon': Icons.bar_chart_rounded,
                  'name': '概率模型',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraPage(appName: 'probability'),
                      ),
                    );
                  },
                },
              ];

              final Map<String, dynamic> tool = tools[index];
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Material(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: tool['onTap'] as VoidCallback,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(tool['icon'] as IconData, color: cs.primary, size: 20),
                              const SizedBox(height: 4),
                              Text(
                                tool['name'] as String,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                launchUrl(
                  Uri.parse('https://www.geogebra.org/materials'),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.people_outline, size: 18),
              label: const Text('GeoGebra 社区'),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildVideoList() {
    final List<VideoResource> videos = _recommendedVideos;

    if (videos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Text('下拉刷新获取推荐视频', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          final VideoResource item = videos[index];
          return _VideoCard(video: item);
        },
      ),
    );
  }
}

class _FunctionWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF9FB3FF).withValues(alpha: 0.5);

    final Path path1 = Path();
    final Path path2 = Path();

    for (double x = 0; x <= size.width; x += 1) {
      final double y1 =
          size.height * 0.58 + 18 * _sinLike(x / size.width * 6.28);
      final double y2 =
          size.height * 0.48 + 12 * _sinLike(x / size.width * 9.42 + 0.5);
      if (x == 0) {
        path1.moveTo(x, y1);
        path2.moveTo(x, y2);
      } else {
        path1.lineTo(x, y1);
        path2.lineTo(x, y2);
      }
    }

    canvas.drawPath(path1, paint);
    canvas.drawPath(
      path2,
      paint..color = const Color(0xFFB8C6FF).withValues(alpha: 0.4),
    );
  }

  double _sinLike(double x) {
    return (x - x * x * x / 6 + x * x * x * x * x / 120).clamp(-1.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VideoCard extends StatefulWidget {
  final VideoResource video;

  const _VideoCard({required this.video});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  ColorScheme get cs => Theme.of(context).colorScheme;

  String? _coverUrl;
  bool _coverLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.video.coverUrl != null) {
      _coverUrl = widget.video.coverUrl;
    } else if (widget.video.bvId.isNotEmpty) {
      _fetchCover();
    }
  }

  Future<void> _fetchCover() async {
    if (_coverLoaded) return;
    try {
      // Web 端走 nginx 代理避免 CORS，移动端直连
      final String apiUrl = kIsWeb
          ? '/api/bilibili/x/web-interface/view?bvid=${widget.video.bvId}'
          : 'https://api.bilibili.com/x/web-interface/view?bvid=${widget.video.bvId}';
      final http.Response response = await http.get(
        Uri.parse(apiUrl),
        headers: kIsWeb ? <String, String>{} : <String, String>{
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Referer': 'https://www.bilibili.com/',
        },
      ).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body) as Map<String, dynamic>;
        final String? pic = data['data']?['pic'] as String?;
        if (pic != null && mounted) {
          setState(() {
            _coverUrl = pic.replaceFirst('http://', 'https://');
            _coverLoaded = true;
          });
        }
      }
    } catch (_) {
      _coverLoaded = true;
    }
  }

  void _openVideo() {
    final String bvId = widget.video.bvId;
    if (bvId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('暂无对应视频'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            VideoPlayerPage(title: widget.video.title, bvId: bvId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openVideo,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cs.surface,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 封面图或占位
              _coverUrl != null
                  ? Image.network(
                      _coverUrl!,
                      fit: BoxFit.cover,
                      width: 160,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  : _buildPlaceholder(),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.video.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.video.grade} · ${widget.video.module}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white,
                  child: Icon(
                    Icons.play_arrow,
                    color: Color(0xFF3F51B5),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: cs.primaryContainer,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.video_library,
            color: cs.primary,
            size: 40,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.video.uploader,
              style: TextStyle(
                color: cs.primary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
class _ChatTransitionRoute extends PageRouteBuilder<void> {
  final Widget targetPage;

  _ChatTransitionRoute({required this.targetPage})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => targetPage,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
                ),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        );
}
