import 'package:flutter/material.dart';
import 'package:mathmate/services/ability_score_service.dart';
import 'package:mathmate/theme/grade_ui_profile.dart';

class GradeMascotOrb extends StatefulWidget {
  const GradeMascotOrb({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<GradeMascotOrb> createState() => _GradeMascotOrbState();
}

class _GradeMascotOrbState extends State<GradeMascotOrb> {
  final AbilityScoreService _abilityService = AbilityScoreService();

  @override
  void initState() {
    super.initState();
    _abilityService.addListener(_onGradeChanged);
  }

  @override
  void dispose() {
    _abilityService.removeListener(_onGradeChanged);
    super.dispose();
  }

  void _onGradeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final GradeUiProfile profile = GradeUiProfile.forGrade(
      _abilityService.currentGrade,
    );
    final _MascotVisual visual = _MascotVisual.forStage(profile.stage);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double size = profile.stage == GradeStage.lowerPrimary
        ? 76
        : profile.stage == GradeStage.upperPrimary
        ? 72
        : 66;

    return Semantics(
      button: true,
      label: '${visual.name}，打开 AI 对话',
      child: Tooltip(
        message: '${visual.name} · 问 AI',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.28 : 0.82),
                width: 1.5,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: profile.primary.withValues(
                    alpha: isDark ? 0.34 : 0.24,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                visual.asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotVisual {
  const _MascotVisual(this.name, this.asset);

  final String name;
  final String asset;

  static _MascotVisual forStage(GradeStage stage) {
    return switch (stage) {
      GradeStage.lowerPrimary => const _MascotVisual(
        '算算精灵',
        'assets/mascots/mascot-primary-lower.png',
      ),
      GradeStage.upperPrimary => const _MascotVisual(
        '探索精灵',
        'assets/mascots/mascot-primary-upper.png',
      ),
      GradeStage.middle => const _MascotVisual(
        '推理精灵',
        'assets/mascots/mascot-middle.png',
      ),
      GradeStage.high => const _MascotVisual(
        '函数精灵',
        'assets/mascots/mascot-high.png',
      ),
      GradeStage.university => const _MascotVisual(
        '研习精灵',
        'assets/mascots/mascot-university.png',
      ),
      GradeStage.research => const _MascotVisual(
        '研究精灵',
        'assets/mascots/mascot-research.png',
      ),
    };
  }
}
