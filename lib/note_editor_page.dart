import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'note_model.dart';
import 'handwriting_page.dart';
import 'history_list_page.dart';

import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class NoteEditorPage extends StatefulWidget {
  final Note? note;
  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  TextEditingController? _tagController;
  late String _selectedCategory;
  List<String> _imagePaths = [];
  List<String> _tags = [];
  bool _hasHistoryLink = false;
  final ImagePicker _picker = ImagePicker();

  late quill.QuillController _quillController;
  int _activeToolbarIndex = 0;

  final GlobalKey _printKey = GlobalKey();

  // 持久的格式状态：当用户通过工具栏设置格式（颜色、粗体等）后，
  // 即使光标移动到其他位置，格式也不会丢失。
  quill.Style _persistedFormat = const quill.Style();

  void _initQuillController(quill.QuillController controller) {
    _quillController = controller;
    _quillController.addListener(() {
      final current = _quillController.toggledStyle;
      if (current.attributes.isEmpty) {
        // toggledStyle 被 _updateSelection 清空（光标移动导致），
        // 保留 _persistedFormat 不变
        return;
      }
      // 用户通过工具栏显式切换了格式
      final validAttrs = Map<String, quill.Attribute>.fromEntries(
        current.attributes.entries
            .where((e) => e.value.value != null),
      );
      _persistedFormat = quill.Style.attr(validAttrs);
    });
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _selectedCategory = widget.note?.category ?? '其他';
    _imagePaths = widget.note?.imagePaths ?? [];
    _tags = widget.note?.tags ?? [];
    _hasHistoryLink = widget.note?.hasHistoryLink ?? false;

    if (widget.note != null && widget.note!.content.isNotEmpty) {
      try {
        final doc = quill.Document.fromJson(jsonDecode(widget.note!.content));
        _initQuillController(quill.QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
          keepStyleOnNewLine: true,
          onSelectionChanged: (_) {
            _restorePersistedFormat();
          },
        ));
      } catch (e) {
        _initQuillController(quill.QuillController(
          document: quill.Document(),
          selection: const TextSelection.collapsed(offset: 0),
          keepStyleOnNewLine: true,
          onSelectionChanged: (_) {
            _restorePersistedFormat();
          },
        ));
      }
    } else {
      _initQuillController(quill.QuillController(
        document: quill.Document(),
        selection: const TextSelection.collapsed(offset: 0),
        keepStyleOnNewLine: true,
        onSelectionChanged: (_) {
          _restorePersistedFormat();
        },
      ));
    }
  }

  void _restorePersistedFormat() {
    if (_persistedFormat.attributes.isEmpty) return;
    // 延迟恢复，确保在 _updateSelection 清空 toggledStyle 之后执行
    Future.microtask(() {
      if (mounted && _persistedFormat.attributes.isNotEmpty) {
        _quillController.forceToggledStyle(_persistedFormat);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  void _saveAndExit() {
    final title = _titleController.text.trim();
    final plainText = _quillController.document.toPlainText().trim();

    if (title.isEmpty && plainText.isEmpty && _imagePaths.isEmpty) {
      Navigator.pop(context, null);
      return;
    }

    final contentJson = jsonEncode(
      _quillController.document.toDelta().toJson(),
    );
    final note = Note(
      title: title,
      content: contentJson,
      createTime: widget.note?.createTime ?? DateTime.now(),
      updateTime: DateTime.now(),
      imagePaths: _imagePaths,
      isFavorite: widget.note?.isFavorite ?? false,
      category: _selectedCategory,
      tags: _tags,
      hasHistoryLink: _hasHistoryLink,
    );
    Navigator.pop(context, note);
  }

  void _showShareMenu() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              top: 24.0,
              bottom: 32.0,
              left: 32.0,
              right: 32.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    "分享笔记",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Kaiti',
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    final title = _titleController.text.trim();
                    final text = _quillController.document.toPlainText().trim();
                    final shareContent = title.isEmpty
                        ? text
                        : "【$title】\n$text";

                    if (shareContent.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('笔记为空，无法分享')),
                      );
                      return;
                    }
                    Share.share(shareContent);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("以文字形式分享", style: TextStyle(fontSize: 18)),
                  ),
                ),

                InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await Future.delayed(const Duration(milliseconds: 200));
                      RenderRepaintBoundary boundary =
                          _printKey.currentContext!.findRenderObject()
                              as RenderRepaintBoundary;
                      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
                      ByteData? byteData = await image.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      if (byteData != null) {
                        final directory = await getTemporaryDirectory();
                        final imageFile = await File(
                          '${directory.path}/note_share.png',
                        ).create();
                        await imageFile.writeAsBytes(
                          byteData.buffer.asUint8List(),
                        );
                        await Share.shareXFiles([
                          XFile(imageFile.path),
                        ], text: '分享笔记图片');
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('图片生成失败，请稍后再试')),
                      );
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("以图片形式分享", style: TextStyle(fontSize: 18)),
                  ),
                ),

                InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    String md = _generateMarkdown();
                    if (md.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('笔记为空，无法导出')),
                      );
                      return;
                    }
                    try {
                      final directory = await getTemporaryDirectory();
                      final title = _titleController.text.trim().isEmpty
                          ? "无标题笔记"
                          : _titleController.text.trim();
                      final mdFile = await File(
                        '${directory.path}/$title.md',
                      ).create();
                      await mdFile.writeAsString(md);
                      await Share.shareXFiles([
                        XFile(mdFile.path),
                      ], text: '导出Markdown文件');
                    } catch (e) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('导出失败')));
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      "以Markdown格式导出",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF0F0F0),
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text("取消", style: TextStyle(fontSize: 18)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _generateMarkdown() {
    final title = _titleController.text.trim();
    StringBuffer md = StringBuffer();
    if (title.isNotEmpty) md.writeln('# $title\n');

    final delta = _quillController.document.toDelta();
    for (var op in delta.toList()) {
      if (op.data is String) {
        String text = op.data as String;
        if (op.attributes != null) {
          if (op.attributes!['bold'] == true) text = '**$text**';
          if (op.attributes!['italic'] == true) text = '*$text*';
          if (op.attributes!['underline'] == true) text = '<u>$text</u>';
        }
        md.write(text);
      }
    }
    return md.toString();
  }

  void _selectCategory() async {
    final predefined = ['代数', '几何', '微积分', '其他'];
    String tempCategory = predefined.contains(_selectedCategory)
        ? _selectedCategory
        : '其他';
    TextEditingController customCatController = TextEditingController(
      text: predefined.contains(_selectedCategory) ? '' : _selectedCategory,
    );

    final String? pickedCategory = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                "选择分类",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...predefined.map(
                    (cat) {
                      final bool selected = tempCategory == cat;
                      return ListTile(
                        title: Text(cat),
                        leading: Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: selected ? Theme.of(context).primaryColor : Colors.grey,
                        ),
                        onTap: () => setState(() => tempCategory = cat),
                      );
                    },
                  ),
                  if (tempCategory == '其他')
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                      ),
                      child: TextField(
                        controller: customCatController,
                        decoration: const InputDecoration(
                          hintText: '请输入自定义标签...',
                          isDense: true,
                          border: UnderlineInputBorder(),
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("取消"),
                ),
                TextButton(
                  onPressed: () {
                    if (tempCategory == '其他' &&
                        customCatController.text.trim().isNotEmpty) {
                      Navigator.pop(context, customCatController.text.trim());
                    } else {
                      Navigator.pop(context, tempCategory);
                    }
                  },
                  child: const Text(
                    "确定",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (pickedCategory != null)
      setState(() => _selectedCategory = pickedCategory);
  }

  void _addTag() {
    _tagController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("添加标签"),
          content: TextField(
            controller: _tagController,
            maxLength: 10,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () {
                final tag = (_tagController?.text ?? '').trim();
                if (tag.isNotEmpty && !_tags.contains(tag))
                  setState(() => _tags.add(tag));
                Navigator.pop(dialogContext);
              },
              child: const Text("添加"),
            ),
          ],
        );
      },
    ).then((_) {
      _tagController?.dispose();
      _tagController = null;
    });
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  void _pickImageFromGallery() async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (pickedFile != null) setState(() => _imagePaths.add(pickedFile.path));
  }

  Widget _buildImagePreview(String path) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0, bottom: 8.0),
      child: Stack(
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              image: DecorationImage(
                image: FileImage(File(path)),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() => _imagePaths.remove(path)),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(widget.note != null ? "编辑笔记" : "新建笔记"),
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _saveAndExit,
          ),
          actions: [
            IconButton(
              onPressed: _showShareMenu,
              icon: const Icon(Icons.ios_share, color: Colors.black87),
            ),
            IconButton(
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('个性化信纸/背景功能开发中'))),
              icon: const Icon(Icons.checkroom, color: Colors.black87),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black87),
              color: Colors.white,
              onSelected: (value) {
                if (value == 'category') _selectCategory();
                if (value == 'link')
                  setState(() => _hasHistoryLink = !_hasHistoryLink);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'category',
                  child: Text('🏷️ 当前分类: $_selectedCategory (点击修改)'),
                ),
                PopupMenuItem(
                  value: 'link',
                  child: Text(_hasHistoryLink ? '🔗 取消关联搜题历史' : '🔗 关联搜题历史'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: RepaintBoundary(
                key: _printKey,
                child: Container(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            hintText: "无标题",
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        if (_tags.isNotEmpty) ...[
                          Wrap(
                            spacing: 8,
                            children: _tags
                                .map(
                                  (tag) => Chip(
                                    label: Text(tag),
                                    onDeleted: () => _removeTag(tag),
                                    backgroundColor: Colors.grey[200],
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (_hasHistoryLink)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HistoryListPage(),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.link,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.blue,
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      '点击查看所有搜题历史',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        quill.QuillEditor.basic(
                          controller: _quillController,
                          config: const quill.QuillEditorConfig(
                            placeholder: '请输入笔记',
                          ),
                        ),

                        if (_imagePaths.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 150,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: _imagePaths
                                  .map(_buildImagePreview)
                                  .toList(),
                            ),
                          ),
                        ],
                        const SizedBox(height: 150),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_activeToolbarIndex != 0)
                    Container(
                      color: Colors.grey.shade50,
                      width: double.infinity,
                      child: quill.QuillSimpleToolbar(
                        controller: _quillController,
                        config: quill.QuillSimpleToolbarConfig(
                          multiRowsDisplay: true,
                          showFontFamily: _activeToolbarIndex == 1,
                          showFontSize: _activeToolbarIndex == 1,
                          showBoldButton: _activeToolbarIndex == 1,
                          showItalicButton: _activeToolbarIndex == 1,
                          showUnderLineButton: _activeToolbarIndex == 1,
                          showColorButton: _activeToolbarIndex == 1,
                          showBackgroundColorButton: _activeToolbarIndex == 1,
                          showAlignmentButtons: _activeToolbarIndex == 2,
                          showHeaderStyle: _activeToolbarIndex == 2,
                          showListNumbers: _activeToolbarIndex == 3,
                          showListBullets: _activeToolbarIndex == 3,
                          showListCheck: _activeToolbarIndex == 3,
                          showQuote: _activeToolbarIndex == 3,
                          showCodeBlock: _activeToolbarIndex == 3,
                          showUndo: false,
                          showRedo: false,
                          showSearchButton: false,
                          showSubscript: false,
                          showSuperscript: false,
                          showClearFormat: false,
                          showLink: false,
                          showIndent: false,
                          showStrikeThrough: false,
                          showClipboardCopy: false,
                          showClipboardCut: false,
                          showClipboardPaste: false,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.text_fields),
                          color: _activeToolbarIndex == 1
                              ? Colors.blue
                              : Colors.black54,
                          onPressed: () => setState(
                            () => _activeToolbarIndex = _activeToolbarIndex == 1
                                ? 0
                                : 1,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.format_align_center),
                          color: _activeToolbarIndex == 2
                              ? Colors.blue
                              : Colors.black54,
                          onPressed: () => setState(
                            () => _activeToolbarIndex = _activeToolbarIndex == 2
                                ? 0
                                : 2,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.format_list_bulleted),
                          color: _activeToolbarIndex == 3
                              ? Colors.blue
                              : Colors.black54,
                          onPressed: () => setState(
                            () => _activeToolbarIndex = _activeToolbarIndex == 3
                                ? 0
                                : 3,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.image_outlined),
                          onPressed: _pickImageFromGallery,
                        ),
                        IconButton(
                          icon: const Icon(Icons.draw_outlined),
                          tooltip: "手写涂鸦",
                          onPressed: () async {
                            FocusManager.instance.primaryFocus
                                ?.unfocus();
                            final Uint8List? pngBytes = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HandwritingPage(),
                              ),
                            );

                            if (pngBytes != null) {
                              final directory = await getTemporaryDirectory();
                              final fileName =
                                  'handwriting_${DateTime.now().millisecondsSinceEpoch}.png';
                              final file = await File(
                                '${directory.path}/$fileName',
                              ).create();
                              await file.writeAsBytes(pngBytes);

                              setState(() {
                                _imagePaths.add(file.path);
                              });
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.sell_outlined),
                          onPressed: _addTag,
                        ),
                        IconButton(
                          icon: const Icon(Icons.keyboard_hide),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            setState(() => _activeToolbarIndex = 0);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
