import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mathmate/library/models/awesome_resource.dart';

/// 资源库列表项（awesome-math 一条资源）
class AwesomeResourceTile extends StatelessWidget {
  final AwesomeMathResource resource;
  const AwesomeResourceTile({super.key, required this.resource});

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: () => _openUrl(context, resource.url),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: cs.primaryContainer,
        child: Icon(resource.type.icon, size: 18, color: cs.primary),
      ),
      title: Text(
        resource.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (resource.subtitle.isNotEmpty)
            Text(
              resource.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          Text(
            resource.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
      trailing: _trailing(cs),
    );
  }

  Widget _trailing(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        _stageChip(cs),
        if (resource.paid)
          Padding(
            padding: EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.paid_outlined, size: 13, color: cs.tertiary),
                const SizedBox(width: 2),
                Text(
                  '付费',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stageChip(ColorScheme cs) {
    final Color bg;
    final Color fg;
    switch (resource.stage) {
      case LearnStage.middle:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
      case LearnStage.undergrad:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      case LearnStage.grad:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
      case LearnStage.general:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(
        resource.stage.label,
        style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法打开: $url'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
