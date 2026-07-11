import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mathmate/library/models/study_material.dart';
import 'package:mathmate/library/presentation/material_upload_sheet.dart';
import 'package:mathmate/library/services/ingestion_service.dart';
import 'package:mathmate/library/services/material_repository.dart';
import 'package:mathmate/library/presentation/resource_library_tab.dart';

/// 资料库入口 —— 顶部分段控件切换「我的资料」与「资源库」两个分区。
///
/// 数据隔离：我的资料 = 用户上传（MaterialRepository）；
/// 资源库 = awesome-math 预置公共资源（CC0）。
/// IndexedStack 保活两分区状态（对齐 responsive_shell.dart 范式）。
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0; // 0=我的资料 1=资源库

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('资料库'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                    value: 0,
                    icon: Icon(Icons.folder_rounded),
                    label: Text('我的资料')),
                ButtonSegment<int>(
                    value: 1,
                    icon: Icon(Icons.public_rounded),
                    label: Text('资源库')),
              ],
              selected: <int>{_tab},
              onSelectionChanged: (Set<int> s) =>
                  setState(() => _tab = s.first),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: const <Widget>[_MyMaterialsTab(), ResourceLibraryTab()],
      ),
    );
  }
}

/// 「我的资料」分区（原 LibraryPage 主体，用户上传私有资料）
///
/// 监听 MaterialRepository.watch 自动刷新。
/// 含：统计头部 + 高校集合卡 + 关键词检索 + 资料卡（缩略图/角标/难度点）+ 空态引导。
class _MyMaterialsTab extends StatefulWidget {
  const _MyMaterialsTab();

  @override
  State<_MyMaterialsTab> createState() => _MyMaterialsTabState();
}

class _MyMaterialsTabState extends State<_MyMaterialsTab> {
  ColorScheme get cs => Theme.of(context).colorScheme;

  StreamSubscription<List<StudyMaterial>>? _sub;
  List<StudyMaterial> _materials = const <StudyMaterial>[];
  String _filterUni = '';
  String _filterCourse = '';
  String _keyword = '';
  bool _busy = false;
  String _busyText = '';

  @override
  void initState() {
    super.initState();
    _materials = MaterialRepository.instance.all();
    _sub = MaterialRepository.instance.watch.listen((List<StudyMaterial> list) {
      if (mounted) {
        _materials = list;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// 当前筛选 + 关键词命中的资料
  List<StudyMaterial> get _filtered {
    List<StudyMaterial> list = _materials;
    if (_filterUni.isNotEmpty) {
      list = list.where((m) => m.university == _filterUni).toList();
    }
    if (_filterCourse.isNotEmpty) {
      list = list.where((m) => m.course == _filterCourse).toList();
    }
    if (_keyword.trim().isNotEmpty) {
      final String kw = _keyword.trim().toLowerCase();
      list = list.where((StudyMaterial m) {
        final String hay = <String>[
          m.title, m.summary, m.subject,
          ...m.knowledgePoints, ...m.keyConcepts,
        ].join(' ').toLowerCase();
        return hay.contains(kw);
      }).toList();
    }
    return list;
  }

  /// 高校 × 课程 分组（供集合卡）
  List<_UniGroup> get _groups {
    final Map<String, _UniGroup> map = <String, _UniGroup>{};
    for (final StudyMaterial m in _materials) {
      final String uni = m.university ?? '其他';
      final String course = m.course ?? '通用';
      final String key = '$uni|$course';
      map.putIfAbsent(key, () => _UniGroup(uni, course)).materials.add(m);
    }
    final List<_UniGroup> groups = map.values.toList();
    groups.sort((a, b) => b.materials.length.compareTo(a.materials.length));
    return groups;
  }

  Future<void> _openUpload() async {
    final MaterialKind? kind = await showModalBottomSheet<MaterialKind>(
      context: context,
      builder: (_) => const MaterialUploadSheet(),
    );
    if (kind == null || !mounted) return;
    setState(() {
      _busy = true;
      _busyText = '正在采集资料…';
    });
    try {
      await IngestionService.instance.ingest(
        kind,
        onProgress: (String t) {
          if (mounted) setState(() => _busyText = t);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: <Widget>[
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('资料已入库，AI 已自动分类')),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('上传失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _busy
          ? _buildBusy()
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(child: _buildStatHeader()),
                if (_materials.isEmpty)
                  SliverFillRemaining(child: _buildEmpty())
                else ...<Widget>[
                  SliverToBoxAdapter(child: _buildSearchField()),
                  if (_groups.length >= 2)
                    SliverToBoxAdapter(child: _buildGroupCards()),
                  if (_filterUni.isNotEmpty || _filterCourse.isNotEmpty)
                    SliverToBoxAdapter(child: _buildActiveFilterChip()),
                  if (_filtered.isEmpty)
                    SliverFillRemaining(child: _buildNoResult())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.70,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext ctx, int i) =>
                              _MaterialCard(material: _filtered[i]),
                          childCount: _filtered.length,
                        ),
                      ),
                    ),
                ],
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _openUpload,
        icon: const Icon(Icons.upload_file),
        label: const Text('上传资料'),
      ),
    );
  }

  // ——— 1. 统计头部 ———
  Widget _buildStatHeader() {
    final int total = _materials.length;
    final int uniCount = MaterialRepository.instance.universities.length;
    final StudyMaterial? latest = _materials.isNotEmpty ? _materials.first : null;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[cs.primary, cs.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.folder_special_rounded, color: cs.onPrimary, size: 18),
              const SizedBox(width: 6),
              Text(
                '我的专属学习资料库',
                style: TextStyle(
                  color: cs.onPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _statValue('$total', '份资料'),
              const SizedBox(width: 24),
              _statValue('$uniCount', '所高校'),
              const SizedBox(width: 20),
              Expanded(
                child: latest == null
                    ? const SizedBox()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '最近上传',
                            style: TextStyle(
                              color: cs.onPrimary.withValues(alpha: 0.75),
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            latest.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statValue(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            color: cs.onPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: cs.onPrimary.withValues(alpha: 0.8),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ——— 搜索框 ———
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索知识点 / 关键词…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onChanged: (String v) => setState(() => _keyword = v),
      ),
    );
  }

  // ——— 2. 高校集合卡（横滚）———
  Widget _buildGroupCards() {
    final List<_UniGroup> groups = _groups;
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, int i) {
          final _UniGroup g = groups[i];
          final bool active =
              _filterUni == g.university && _filterCourse == g.course;
          return _groupCard(g, active);
        },
      ),
    );
  }

  Widget _groupCard(_UniGroup g, bool active) {
    final Color bg = active ? cs.primary : cs.surfaceContainerHighest;
    final Color fg = active ? cs.onPrimary : cs.onSurface;
    return GestureDetector(
      onTap: () => setState(() {
        if (active) {
          _filterUni = '';
          _filterCourse = '';
        } else {
          _filterUni = g.university;
          _filterCourse = g.course;
        }
      }),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.school_rounded,
                    size: 15, color: active ? cs.onPrimary : cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    g.university,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              g.course,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: active ? cs.onPrimary.withValues(alpha: 0.85) : cs.onSurfaceVariant,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  '${g.materials.length}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: active ? cs.onPrimary : cs.primary,
                  ),
                ),
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '份',
                    style: TextStyle(
                      fontSize: 10,
                      color: active ? cs.onPrimary.withValues(alpha: 0.85) : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ——— 激活的筛选标签（点 × 清除）———
  Widget _buildActiveFilterChip() {
    final String label = '$_filterUni${_filterCourse.isNotEmpty ? ' · $_filterCourse' : ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          deleteIcon: const Icon(Icons.close, size: 16),
          onDeleted: () => setState(() {
            _filterUni = '';
            _filterCourse = '';
          }),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  // ——— 4. 空态引导 ———
  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_open_rounded, size: 48, color: cs.primary),
            ),
            const SizedBox(height: 20),
            const Text('资料库还是空的',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '上传你的学习资料，AI 帮你自动分类整理\n期末复习一键找回，按高校归档',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 24),
            _buildSteps(),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('上传第一份资料'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSteps() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _step(Icons.upload_outlined, '上传'),
        _arrow(),
        _step(Icons.auto_awesome_rounded, 'AI 分类'),
        _arrow(),
        _step(Icons.bookmark_added_outlined, '随时复习'),
      ],
    );
  }

  Widget _step(IconData icon, String label) {
    return Column(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ],
    );
  }

  Widget _arrow() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Colors.grey),
      );

  Widget _buildNoResult() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off_rounded, size: 56, color: cs.outline),
            const SizedBox(height: 8),
            Text('没有匹配的资料', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );

  Widget _buildBusy() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_busyText, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
}

/// 高校 × 课程 分组
class _UniGroup {
  final String university;
  final String course;
  final List<StudyMaterial> materials = <StudyMaterial>[];
  _UniGroup(this.university, this.course);
}

/// 资料卡（缩略图 + 类型角标 + 难度点 + 知识点）
class _MaterialCard extends StatelessWidget {
  final StudyMaterial material;
  const _MaterialCard({required this.material});

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(flex: 3, child: _buildThumb(cs)),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(_kindIconData(), size: 13, color: cs.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          material.kind.displayName,
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _difficultyDot(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      material.title,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (material.university != null)
                    Row(
                      children: <Widget>[
                        Icon(Icons.school_rounded, size: 10, color: cs.tertiary),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            material.university!,
                            style: TextStyle(fontSize: 9.5, color: cs.tertiary, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    children: material.knowledgePoints
                        .take(3)
                        .map((String k) => _tag(k, cs))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 缩略图区：图片类型显示真图，其他显示类型色块 + 大图标
  Widget _buildThumb(ColorScheme cs) {
    final String badgeLabel =
        material.materialType.isNotEmpty ? material.materialType : material.kind.displayName;
    if (material.kind == MaterialKind.image && File(material.localPath).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.file(File(material.localPath), fit: BoxFit.cover),
          Positioned(left: 6, bottom: 6, child: _typeBadge(badgeLabel)),
        ],
      );
    }
    return Container(
      color: _kindBg(cs),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: Icon(_kindIconData(), size: 40, color: cs.primary.withValues(alpha: 0.55)),
          ),
          Positioned(left: 6, bottom: 6, child: _typeBadge(badgeLabel)),
        ],
      ),
    );
  }

  IconData _kindIconData() => <MaterialKind, IconData>{
        MaterialKind.pdf: Icons.picture_as_pdf_rounded,
        MaterialKind.pptx: Icons.slideshow_rounded,
        MaterialKind.image: Icons.image_rounded,
        MaterialKind.audio: Icons.graphic_eq_rounded,
      }[material.kind] ??
      Icons.insert_drive_file_rounded;

  Color _kindBg(ColorScheme cs) => <MaterialKind, Color>{
        MaterialKind.pdf: Colors.red.withValues(alpha: 0.08),
        MaterialKind.pptx: Colors.orange.withValues(alpha: 0.08),
        MaterialKind.image: cs.primaryContainer,
        MaterialKind.audio: Colors.purple.withValues(alpha: 0.08),
      }[material.kind] ??
      cs.surfaceContainerHighest;

  Widget _typeBadge(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w500),
        ),
      );

  Widget _difficultyDot() {
    final Color color = <String, Color>{
      '基础': Colors.green,
      '中等': Colors.orange,
      '挑战': Colors.red,
    }[material.difficulty] ??
        Colors.grey;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _tag(String text, ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 9.5, color: cs.onPrimaryContainer),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}
