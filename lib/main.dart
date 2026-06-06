import 'dart:convert';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
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
import 'package:mathmate/services/provider_config_service.dart';
import 'package:mathmate/services/theme_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mathmate/services/video_recommendation_service.dart';
import 'package:mathmate/theme/app_theme.dart';
import 'package:mathmate/tutorial_page.dart';
import 'package:mathmate/pages/geogebra_chat_entry.dart';

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
  await ProviderConfigService.instance.init();

  final bool isFirst = kIsWeb ? true : await HistoryRepository.instance.isFirstLaunch();
  final bool tutorialCompleted = kIsWeb ? false : await HistoryRepository.instance.isTutorialCompleted();
  runApp(MathMateApp(
    checkFirstLaunch: isFirst,
    showTutorial: !tutorialCompleted && !isFirst,
  ));
}

class MathMateApp extends StatefulWidget {
  final bool checkFirstLaunch;
  final bool showTutorial;

  const MathMateApp({super.key, required this.checkFirstLaunch, this.showTutorial = false});

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
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const <Widget>[QuestionHomePage(), NotesPage(), ProfilePage()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: '题目',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_border_rounded),
            label: '笔记',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            label: '我的',
          ),
        ],
      ),
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
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
    });

    final dynamic scannedResult = await _scannerService.startScanning(context);

    if (!mounted) {
      return;
    }

    if (scannedResult == null) {
      setState(() {
        _isScanning = false;
      });
      return;
    }

    setState(() {
      _isScanning = false;
    });

    final XFile? croppedFile = await Navigator.of(context).push<XFile>(
      MaterialPageRoute(
        builder: (_) => EnhancedCropPage(imageFile: scannedResult as XFile),
      ),
    );

    if (!mounted) {
      return;
    }

    if (croppedFile == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BeautifulResultPage(image: croppedFile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWide = screenWidth > 700;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 800 : double.infinity),
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
                    const SizedBox(height: 18),
                    _buildCameraHero(),
                    const SizedBox(height: 14),
                _buildToolboxCard(),
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
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索题目或问蓝心助手...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _openSearchChat(),
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(_ChatTransitionRoute(
                targetPage: const ChatHomePage(),
              ));
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryListPage()),
              );
            },
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraHero() {
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.5,
            ),
            itemCount: 7,
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
                <String, dynamic>{
                  'icon': Icons.auto_awesome,
                  'name': 'GeoGebra 助手',
                  'onTap': () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GeogebraChatPage(),
                      ),
                    );
                  },
                },
              ];

              final Map<String, dynamic> tool = tools[index];
              return GestureDetector(
                onTap: tool['onTap'] as VoidCallback,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          tool['icon'] as IconData,
                          color: cs.primary,
                          size: 22,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tool['name'] as String,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
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
