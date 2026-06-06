import 'package:flutter/material.dart';
import 'package:mathmate/services/provider_config_service.dart';

class ProviderSettingsPage extends StatefulWidget {
  const ProviderSettingsPage({super.key});

  @override
  State<ProviderSettingsPage> createState() => _ProviderSettingsPageState();
}

class _ProviderSettingsPageState extends State<ProviderSettingsPage> {
  final ProviderConfigService _config = ProviderConfigService.instance;

  // vision controllers
  late TextEditingController _visionApiKeyCtrl;
  late TextEditingController _visionModelIdCtrl;
  late TextEditingController _visionBaseUrlCtrl;

  // reasoning controllers
  late TextEditingController _reasoningApiKeyCtrl;
  late TextEditingController _reasoningModelIdCtrl;
  late TextEditingController _reasoningBaseUrlCtrl;

  // chat controllers
  late TextEditingController _chatApiKeyCtrl;
  late TextEditingController _chatModelIdCtrl;
  late TextEditingController _chatBaseUrlCtrl;

  // temperature controllers
  late TextEditingController _visionTempCtrl;
  late TextEditingController _reasoningTempCtrl;
  late TextEditingController _chatTempCtrl;

  // password visibility
  bool _visionKeyVisible = false;
  bool _reasoningKeyVisible = false;
  bool _chatKeyVisible = false;

  // model fetch state (0=vision, 1=reasoning, 2=chat)
  final List<bool> _fetchingModels = <bool>[false, false, false];
  final List<ModelFetchResult?> _modelResults = <ModelFetchResult?>[null, null, null];

  @override
  void initState() {
    super.initState();
    _visionApiKeyCtrl = TextEditingController(text: _config.visionApiKey);
    _visionModelIdCtrl = TextEditingController(text: _config.visionModelId);
    _visionBaseUrlCtrl = TextEditingController(text: _config.visionBaseUrl);
    _reasoningApiKeyCtrl = TextEditingController(text: _config.reasoningApiKey);
    _reasoningModelIdCtrl = TextEditingController(text: _config.reasoningModelId);
    _reasoningBaseUrlCtrl = TextEditingController(text: _config.reasoningBaseUrl);
    _chatApiKeyCtrl = TextEditingController(text: _config.chatApiKey);
    _chatModelIdCtrl = TextEditingController(text: _config.chatModelId);
    _chatBaseUrlCtrl = TextEditingController(text: _config.chatBaseUrl);
    _visionTempCtrl = TextEditingController(text: _config.visionTemperature.toString());
    _reasoningTempCtrl = TextEditingController(text: _config.reasoningTemperature.toString());
    _chatTempCtrl = TextEditingController(text: _config.chatTemperature.toString());
    _config.addListener(_onConfigChanged);
  }

  Future<void> _fetchModels(int slotIndex) async {
    if (_fetchingModels[slotIndex]) return;
    final String baseUrl = slotIndex == 0
        ? _visionBaseUrlCtrl.text.trim()
        : slotIndex == 1
            ? _reasoningBaseUrlCtrl.text.trim()
            : _chatBaseUrlCtrl.text.trim();
    final String apiKey = slotIndex == 0
        ? _visionApiKeyCtrl.text.trim()
        : slotIndex == 1
            ? _reasoningApiKeyCtrl.text.trim()
            : _chatApiKeyCtrl.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 API Key 和接口地址')),
      );
      return;
    }

    setState(() => _fetchingModels[slotIndex] = true);
    final ModelFetchResult result = await ProviderConfigService.fetchModels(
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    if (mounted) {
      setState(() {
        _fetchingModels[slotIndex] = false;
        _modelResults[slotIndex] = result;
      });
    }
  }

  void _selectModel(int slotIndex, String modelId) {
    TextEditingController ctrl;
    switch (slotIndex) {
      case 0: ctrl = _visionModelIdCtrl; _config.setVisionModelId(modelId);
      case 1: ctrl = _reasoningModelIdCtrl; _config.setReasoningModelId(modelId);
      case 2: ctrl = _chatModelIdCtrl; _config.setChatModelId(modelId);
      default: return;
    }
    ctrl.text = modelId;
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    _visionApiKeyCtrl.dispose();
    _visionModelIdCtrl.dispose();
    _visionBaseUrlCtrl.dispose();
    _reasoningApiKeyCtrl.dispose();
    _reasoningModelIdCtrl.dispose();
    _reasoningBaseUrlCtrl.dispose();
    _chatApiKeyCtrl.dispose();
    _chatModelIdCtrl.dispose();
    _chatBaseUrlCtrl.dispose();
    _visionTempCtrl.dispose();
    _reasoningTempCtrl.dispose();
    _chatTempCtrl.dispose();
    super.dispose();
  }

  void _onConfigChanged() {
    if (!mounted) return;
    // Sync controllers that haven't been edited by user
    _syncIfDifferent(_visionApiKeyCtrl, _config.visionApiKey);
    _syncIfDifferent(_visionModelIdCtrl, _config.visionModelId);
    _syncIfDifferent(_visionBaseUrlCtrl, _config.visionBaseUrl);
    _syncIfDifferent(_reasoningApiKeyCtrl, _config.reasoningApiKey);
    _syncIfDifferent(_reasoningModelIdCtrl, _config.reasoningModelId);
    _syncIfDifferent(_reasoningBaseUrlCtrl, _config.reasoningBaseUrl);
    _syncIfDifferent(_chatApiKeyCtrl, _config.chatApiKey);
    _syncIfDifferent(_chatModelIdCtrl, _config.chatModelId);
    _syncIfDifferent(_chatBaseUrlCtrl, _config.chatBaseUrl);
    _syncIfDifferent(_visionTempCtrl, _config.visionTemperature.toString());
    _syncIfDifferent(_reasoningTempCtrl, _config.reasoningTemperature.toString());
    _syncIfDifferent(_chatTempCtrl, _config.chatTemperature.toString());
  }

  void _syncIfDifferent(TextEditingController ctrl, String value) {
    if (ctrl.text != value) {
      ctrl.text = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('AI 模型配置'),
        backgroundColor: cs.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _buildSlotSection(
            cs: cs,
            title: '多模态识别',
            subtitle: '拍照搜题 · 手写识别 · 公式分析',
            presetValue: _config.visionProviderId,
            onPresetChanged: (String id) {
              _config.setVisionProviderId(id);
              final String url = ProviderConfigService.baseUrlForPreset(id);
              _visionBaseUrlCtrl.text = url;
              _config.setVisionBaseUrl(url);
            },
            apiKeyCtrl: _visionApiKeyCtrl,
            onApiKeyChanged: (String v) => _config.setVisionApiKey(v),
            modelIdCtrl: _visionModelIdCtrl,
            onModelIdChanged: (String v) => _config.setVisionModelId(v),
            baseUrlCtrl: _visionBaseUrlCtrl,
            onBaseUrlChanged: (String v) => _config.setVisionBaseUrl(v),
            keyVisible: _visionKeyVisible,
            onToggleKeyVisibility: () => setState(() => _visionKeyVisible = !_visionKeyVisible),
            isConfigured: _config.isVisionConfigured,
            onReset: () {
              _config.resetVision();
              _syncControllersFromConfig();
            },
            slotIndex: 0,
            fetchingModels: _fetchingModels[0],
            modelResult: _modelResults[0],
          ),
          const SizedBox(height: 24),
          _buildSlotSection(
            cs: cs,
            title: '解题推理',
            subtitle: '数学求解 · 几何可视化',
            presetValue: _config.reasoningProviderId,
            onPresetChanged: (String id) {
              _config.setReasoningProviderId(id);
              final String url = ProviderConfigService.baseUrlForPreset(id);
              _reasoningBaseUrlCtrl.text = url;
              _config.setReasoningBaseUrl(url);
            },
            apiKeyCtrl: _reasoningApiKeyCtrl,
            onApiKeyChanged: (String v) => _config.setReasoningApiKey(v),
            modelIdCtrl: _reasoningModelIdCtrl,
            onModelIdChanged: (String v) => _config.setReasoningModelId(v),
            baseUrlCtrl: _reasoningBaseUrlCtrl,
            onBaseUrlChanged: (String v) => _config.setReasoningBaseUrl(v),
            keyVisible: _reasoningKeyVisible,
            onToggleKeyVisibility: () => setState(() => _reasoningKeyVisible = !_reasoningKeyVisible),
            isConfigured: _config.isReasoningConfigured,
            onReset: () {
              _config.resetReasoning();
              _syncControllersFromConfig();
            },
            slotIndex: 1,
            fetchingModels: _fetchingModels[1],
            modelResult: _modelResults[1],
          ),
          const SizedBox(height: 24),
          _buildSlotSection(
            cs: cs,
            title: 'AI 对话',
            subtitle: '流式聊天 · 视频推荐 · GeoGebra',
            presetValue: _config.chatProviderId,
            onPresetChanged: (String id) {
              _config.setChatProviderId(id);
              final String url = ProviderConfigService.baseUrlForPreset(id);
              _chatBaseUrlCtrl.text = url;
              _config.setChatBaseUrl(url);
            },
            apiKeyCtrl: _chatApiKeyCtrl,
            onApiKeyChanged: (String v) => _config.setChatApiKey(v),
            modelIdCtrl: _chatModelIdCtrl,
            onModelIdChanged: (String v) => _config.setChatModelId(v),
            baseUrlCtrl: _chatBaseUrlCtrl,
            onBaseUrlChanged: (String v) => _config.setChatBaseUrl(v),
            keyVisible: _chatKeyVisible,
            onToggleKeyVisibility: () => setState(() => _chatKeyVisible = !_chatKeyVisible),
            isConfigured: _config.isChatConfigured,
            onReset: () {
              _config.resetChat();
              _syncControllersFromConfig();
            },
            slotIndex: 2,
            fetchingModels: _fetchingModels[2],
            modelResult: _modelResults[2],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _syncControllersFromConfig() {
    _visionApiKeyCtrl.text = _config.visionApiKey;
    _visionModelIdCtrl.text = _config.visionModelId;
    _visionBaseUrlCtrl.text = _config.visionBaseUrl;
    _reasoningApiKeyCtrl.text = _config.reasoningApiKey;
    _reasoningModelIdCtrl.text = _config.reasoningModelId;
    _reasoningBaseUrlCtrl.text = _config.reasoningBaseUrl;
    _chatApiKeyCtrl.text = _config.chatApiKey;
    _chatModelIdCtrl.text = _config.chatModelId;
    _chatBaseUrlCtrl.text = _config.chatBaseUrl;
    _visionTempCtrl.text = _config.visionTemperature.toString();
    _reasoningTempCtrl.text = _config.reasoningTemperature.toString();
    _chatTempCtrl.text = _config.chatTemperature.toString();
  }

  TextEditingController _temperatureCtrl(int slotIndex) {
    switch (slotIndex) {
      case 0: return _visionTempCtrl;
      case 1: return _reasoningTempCtrl;
      case 2: return _chatTempCtrl;
      default: return _visionTempCtrl;
    }
  }

  String _temperatureDisplay(int slotIndex) {
    final double t = slotIndex == 0
        ? _config.visionTemperature
        : slotIndex == 1
            ? _config.reasoningTemperature
            : _config.chatTemperature;
    return t.toStringAsFixed(1);
  }

  void _setTemperature(int slotIndex, double value) {
    switch (slotIndex) {
      case 0: _config.setVisionTemperature(value);
      case 1: _config.setReasoningTemperature(value);
      case 2: _config.setChatTemperature(value);
    }
  }

  Widget _buildSlotSection({
    required ColorScheme cs,
    required String title,
    required String subtitle,
    required String presetValue,
    required ValueChanged<String> onPresetChanged,
    required TextEditingController apiKeyCtrl,
    required ValueChanged<String> onApiKeyChanged,
    required TextEditingController modelIdCtrl,
    required ValueChanged<String> onModelIdChanged,
    required TextEditingController baseUrlCtrl,
    required ValueChanged<String> onBaseUrlChanged,
    required bool keyVisible,
    required VoidCallback onToggleKeyVisibility,
    required bool isConfigured,
    required VoidCallback onReset,
    required int slotIndex,
    required bool fetchingModels,
    required ModelFetchResult? modelResult,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Status indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isConfigured
                      ? cs.primaryContainer.withValues(alpha: 0.6)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isConfigured ? '已配置' : '未配置',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isConfigured ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Provider preset dropdown
          _buildLabel(cs, '服务商'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: presetValue,
            decoration: _inputDecoration(cs),
            items: kProviderPresets.map((Map<String, String> p) {
              return DropdownMenuItem<String>(
                value: p['id'],
                child: Text(p['name']!, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
            onChanged: (String? v) {
              if (v != null) onPresetChanged(v);
            },
          ),
          const SizedBox(height: 14),

          // API Key
          _buildLabel(cs, 'API Key'),
          const SizedBox(height: 6),
          TextField(
            controller: apiKeyCtrl,
            obscureText: !keyVisible,
            onChanged: onApiKeyChanged,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(cs).copyWith(
              hintText: '输入 API Key',
              suffixIcon: IconButton(
                icon: Icon(
                  keyVisible ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: onToggleKeyVisibility,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Model ID
          Row(
            children: <Widget>[
              Expanded(child: _buildLabel(cs, '模型 ID')),
              TextButton.icon(
                onPressed: fetchingModels ? null : () => _fetchModels(slotIndex),
                icon: fetchingModels
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      )
                    : Icon(Icons.refresh, size: 16, color: cs.primary),
                label: Text(
                  fetchingModels ? '获取中...' : '获取模型',
                  style: TextStyle(fontSize: 12, color: cs.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: modelIdCtrl,
            onChanged: onModelIdChanged,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(cs).copyWith(
              hintText: '输入模型标识符',
            ),
          ),
          // Show fetched models as chips
          if (modelResult != null) ...[
            if (modelResult.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  modelResult.error!,
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              )
            else ...[
              if (modelResult.recommended.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('推荐模型', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: modelResult.recommended.map((String id) => _ModelChip(
                    label: id,
                    isSelected: id == modelIdCtrl.text,
                    onTap: () => _selectModel(slotIndex, id),
                  )).toList(),
                ),
              ],
              if (modelResult.others.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('其他模型', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: modelResult.others.map((String id) => _ModelChip(
                    label: id,
                    isSelected: id == modelIdCtrl.text,
                    onTap: () => _selectModel(slotIndex, id),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 4),
            ],
          ],
          const SizedBox(height: 14),

          // Base URL
          _buildLabel(cs, '接口地址'),
          const SizedBox(height: 6),
          TextField(
            controller: baseUrlCtrl,
            onChanged: onBaseUrlChanged,
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(cs).copyWith(
              hintText: 'API 端点 URL',
            ),
          ),
          const SizedBox(height: 14),

          // Temperature
          Row(
            children: <Widget>[
              _buildLabel(cs, 'Temperature'),
              const SizedBox(width: 8),
              Text(
                '(Kimi K2=1.0, v1=0.6, 其他=0.7)',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _temperatureCtrl(slotIndex),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (String v) {
              final double? t = double.tryParse(v.trim());
              if (t != null && t >= 0 && t <= 2.0) {
                _setTemperature(slotIndex, t);
              } else {
                // 无效输入，恢复原值
                _temperatureCtrl(slotIndex).text = _temperatureDisplay(slotIndex);
              }
            },
            style: const TextStyle(fontSize: 14),
            decoration: _inputDecoration(cs).copyWith(
              hintText: '0.6 ~ 1.0',
            ),
          ),
          const SizedBox(height: 12),

          // Reset button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext ctx) => AlertDialog(
                    title: const Text('重置为默认？'),
                    content: Text('将「$title」的所有配置恢复为 .env 中的默认值。'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onReset();
                        },
                        child: Text('重置', style: TextStyle(color: cs.error)),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.restore, size: 16, color: cs.onSurfaceVariant),
              label: Text(
                '重置为默认',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(ColorScheme cs, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
      ),
    );
  }

  InputDecoration _inputDecoration(ColorScheme cs) {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      isDense: true,
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: cs.primary, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? cs.primary : cs.onSurface,
          ),
        ),
      ),
    );
  }
}
