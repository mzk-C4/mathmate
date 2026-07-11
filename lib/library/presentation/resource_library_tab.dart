import 'package:flutter/material.dart';
import 'package:mathmate/library/models/awesome_resource.dart';
import 'package:mathmate/library/presentation/awesome_resource_tile.dart';
import 'package:mathmate/library/services/awesome_math_repository.dart';

/// 资料库「资源库」分区 —— 展示 awesome-math 预置资源（CC0）。
///
/// 与「我的资料」（用户上传 StudyMaterial）数据完全隔离。
/// 筛选：学段 / 类型 / 分类 + 关键词搜索，点击资源项用 url_launcher 打开外链。
class ResourceLibraryTab extends StatefulWidget {
  const ResourceLibraryTab({super.key});

  @override
  State<ResourceLibraryTab> createState() => _ResourceLibraryTabState();
}

class _ResourceLibraryTabState extends State<ResourceLibraryTab> {
  ColorScheme get cs => Theme.of(context).colorScheme;

  bool _loading = true;
  LearnStage? _stage; // null = 全部
  ResourceType? _type; // null = 全部
  String? _category; // null = 全部（section2）
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await AwesomeMathRepository.instance.load();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<AwesomeMathResource> get _filtered =>
      AwesomeMathRepository.instance.filter(
        stage: _stage,
        type: _type,
        category: _category,
        keyword: _keyword,
      );

  bool get _hasFilter =>
      _stage != null ||
      _type != null ||
      (_category != null && _category!.isNotEmpty) ||
      _keyword.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('加载资源库…', style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    final List<AwesomeMathResource> list = _filtered;
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _buildStageChips()),
        SliverToBoxAdapter(child: _buildTypeChips()),
        SliverToBoxAdapter(child: _buildSearchField()),
        SliverToBoxAdapter(child: _buildCategoryChips()),
        if (_hasFilter) SliverToBoxAdapter(child: _buildActiveFilters()),
        SliverToBoxAdapter(child: _buildCountBar(list.length)),
        if (list.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyResult(),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext ctx, int i) =>
                  AwesomeResourceTile(resource: list[i]),
              childCount: list.length,
            ),
          ),
      ],
    );
  }

  // ——— 学段横滚 ———
  Widget _buildStageChips() => _chipRow(
        items: <_ChipItem<LearnStage>>[
          const _ChipItem(label: '全部', value: null),
          _ChipItem(label: LearnStage.middle.label, value: LearnStage.middle),
          _ChipItem(
              label: LearnStage.undergrad.label, value: LearnStage.undergrad),
          _ChipItem(label: LearnStage.grad.label, value: LearnStage.grad),
        ],
        selected: _stage,
        onSelect: (LearnStage? v) => setState(() => _stage = v),
      );

  // ——— 类型横滚 ———
  Widget _buildTypeChips() => _chipRow(
        items: <_ChipItem<ResourceType>>[
          const _ChipItem(label: '全部', value: null),
          _ChipItem(label: ResourceType.book.label, value: ResourceType.book),
          _ChipItem(label: ResourceType.video.label, value: ResourceType.video),
          _ChipItem(label: ResourceType.notes.label, value: ResourceType.notes),
          _ChipItem(label: ResourceType.link.label, value: ResourceType.link),
        ],
        selected: _type,
        onSelect: (ResourceType? v) => setState(() => _type = v),
      );

  // ——— 分类横滚（section2）———
  Widget _buildCategoryChips() {
    final List<String> cats = AwesomeMathRepository.instance.categories;
    return _chipRow(
      items: <_ChipItem<String>>[
        const _ChipItem(label: '全部分类', value: null),
        ...cats.map((String c) => _ChipItem(label: c, value: c)),
      ],
      selected: _category,
      onSelect: (String? v) => setState(() => _category = v),
    );
  }

  /// 通用横滚 chip 行
  Widget _chipRow<T>({
    required List<_ChipItem<T>> items,
    required T? selected,
    required void Function(T?) onSelect,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 0),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 16),
          itemCount: items.length,
          separatorBuilder: (BuildContext _, int _) => const SizedBox(width: 8),
          itemBuilder: (BuildContext _, int i) {
            final _ChipItem<T> it = items[i];
            final bool active =
                it.value == null ? selected == null : selected == it.value;
            return ChoiceChip(
              label: Text(it.label, style: const TextStyle(fontSize: 12)),
              selected: active,
              onSelected: (_) {
                if (it.value == null || active) {
                  onSelect(null);
                } else {
                  onSelect(it.value);
                }
              },
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索资源标题 / 作者 / 关键词…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (String v) => setState(() => _keyword = v),
      ),
    );
  }

  Widget _buildActiveFilters() {
    final List<String> labels = <String>[];
    if (_stage != null) labels.add('学段: ${_stage!.label}');
    if (_type != null) labels.add('类型: ${_type!.label}');
    if (_category != null && _category!.isNotEmpty) {
      labels.add('分类: $_category');
    }
    if (_keyword.trim().isNotEmpty) labels.add('搜索: ${_keyword.trim()}');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: labels
            .map((String l) => Chip(
                  label: Text(l, style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => setState(() {
                    _stage = null;
                    _type = null;
                    _category = null;
                    _keyword = '';
                  }),
                  visualDensity: VisualDensity.compact,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCountBar(int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Text(
        '共 $n 条资源',
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _ChipItem<T> {
  final String label;
  final T? value;
  const _ChipItem({required this.label, this.value});
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();
  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: 56, color: cs.outline),
          const SizedBox(height: 8),
          Text('没有匹配的资源', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
