import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mathmate/services/api_config_service.dart';
import 'package:mathmate/services/auth_service.dart';

class ApiSettingsPage extends StatefulWidget {
  const ApiSettingsPage({super.key});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _visionModelController = TextEditingController();

  ApiProvider _provider = ApiProvider.deepseek;
  bool _enabled = false;
  bool _obscureKey = true;
  bool _loading = true;
  bool _testing = false;
  String _requestFormat = 'auto';

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _visionModelController.dispose();
    super.dispose();
  }

  Future<void> _loadProvider() async {
    setState(() => _loading = true);
    final ApiProviderConfig config = await ApiConfigService.instance.load(
      _provider,
    );
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _apiKeyController.text = config.apiKey;
      _baseUrlController.text = config.baseUrl;
      _modelController.text = config.modelId;
      _visionModelController.text = config.visionModelId;
      _requestFormat = config.requestFormat;
      _loading = false;
    });
  }

  ApiProviderConfig _currentConfig() => ApiProviderConfig(
    enabled: _enabled,
    apiKey: _apiKeyController.text,
    baseUrl: _baseUrlController.text,
    modelId: _modelController.text,
    visionModelId: _visionModelController.text,
    requestFormat: _requestFormat,
  );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '此项不能为空' : null;

  String? _validateUrl(String? value) {
    final String? requiredError = _required(value);
    if (requiredError != null) return requiredError;
    final Uri? uri = Uri.tryParse(value!.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '请输入完整接口地址';
    }
    if (uri.scheme != 'https' && uri.host != 'localhost') {
      return '网页端请使用 HTTPS 接口';
    }
    return null;
  }

  Future<void> _save() async {
    if (_enabled && !_formKey.currentState!.validate()) return;
    await ApiConfigService.instance.save(_provider, _currentConfig());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_provider.displayName} 配置已保存到当前浏览器')),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final ApiProviderConfig config = _currentConfig();
    setState(() => _testing = true);
    try {
      final http.Response response = await http
          .post(
            Uri.parse(config.baseUrl.trim()),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
              ...AuthService().proxyAuthHeaders,
            },
            body: jsonEncode(<String, dynamic>{
              'model': config.modelId.trim(),
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': '回复 OK'},
              ],
              'max_tokens': 8,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      final bool ok = response.statusCode >= 200 && response.statusCode < 300;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '连接成功' : '连接失败：HTTP ${response.statusCode}'),
          backgroundColor: ok ? Colors.green.shade700 : null,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('连接失败：$error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearCurrent() async {
    await ApiConfigService.instance.clear(_provider);
    await _loadProvider();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_provider.displayName} 自定义配置已清除')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI API 配置')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SegmentedButton<ApiProvider>(
                            segments: ApiProvider.values
                                .map(
                                  (ApiProvider item) =>
                                      ButtonSegment<ApiProvider>(
                                        value: item,
                                        label: Text(item.displayName),
                                      ),
                                )
                                .toList(),
                            selected: <ApiProvider>{_provider},
                            onSelectionChanged: (Set<ApiProvider> value) async {
                              _provider = value.first;
                              await _loadProvider();
                            },
                          ),
                          const SizedBox(height: 24),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('使用自定义 API'),
                            subtitle: const Text('关闭时使用 MathMate 默认服务'),
                            value: _enabled,
                            onChanged: (bool value) =>
                                setState(() => _enabled = value),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Icons.privacy_tip_outlined,
                                  color: colors.onSecondaryContainer,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'API Key 仅保存在当前浏览器的本地存储中，不会提交到 MathMate 账户。请勿在公共电脑保存；自定义接口还需支持浏览器跨域访问。',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'API Key',
                              prefixIcon: const Icon(Icons.key_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            validator: _required,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _baseUrlController,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: '接口地址',
                              prefixIcon: Icon(Icons.link_rounded),
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateUrl,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _modelController,
                            decoration: const InputDecoration(
                              labelText: '模型 ID',
                              prefixIcon: Icon(Icons.smart_toy_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: _required,
                          ),
                          if (_provider == ApiProvider.volc) ...<Widget>[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _visionModelController,
                              decoration: const InputDecoration(
                                labelText: '视觉 / OCR 模型 ID（可选）',
                                prefixIcon: Icon(
                                  Icons.document_scanner_outlined,
                                ),
                                helperText: '留空时使用上面的模型 ID',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _requestFormat,
                              decoration: const InputDecoration(
                                labelText: '请求格式',
                                border: OutlineInputBorder(),
                              ),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem(
                                  value: 'auto',
                                  child: Text('自动'),
                                ),
                                DropdownMenuItem(
                                  value: 'messages',
                                  child: Text('Messages'),
                                ),
                                DropdownMenuItem(
                                  value: 'input',
                                  child: Text('Input'),
                                ),
                              ],
                              onChanged: (String? value) => setState(
                                () => _requestFormat = value ?? 'auto',
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              FilledButton.icon(
                                onPressed: _save,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('保存配置'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _testing ? null : _testConnection,
                                icon: _testing
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.network_check_rounded),
                                label: const Text('测试连接'),
                              ),
                              TextButton.icon(
                                onPressed: _clearCurrent,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('清除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
