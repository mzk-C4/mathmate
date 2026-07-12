import 'package:flutter/material.dart';

enum GradeStage {
  lowerPrimary,
  upperPrimary,
  middle,
  high,
  university,
  research,
}

@immutable
class GradeUiProfile {
  const GradeUiProfile({
    required this.stage,
    required this.gradeLabel,
    required this.modeLabel,
    required this.primary,
    required this.secondary,
    required this.surfaceTint,
    required this.icon,
    required this.backgroundAlignment,
    required this.cardRadius,
    required this.cameraDiameter,
    required this.cameraHeight,
    required this.formula,
    required this.formulaAlignment,
  });

  final GradeStage stage;
  final String gradeLabel;
  final String modeLabel;
  final Color primary;
  final Color secondary;
  final Color surfaceTint;
  final IconData icon;
  final Alignment backgroundAlignment;
  final double cardRadius;
  final double cameraDiameter;
  final double cameraHeight;
  final String formula;
  final Alignment formulaAlignment;

  bool get isCompact =>
      stage == GradeStage.high ||
      stage == GradeStage.university ||
      stage == GradeStage.research;

  LinearGradient get actionGradient => LinearGradient(
    colors: <Color>[primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static GradeUiProfile forGrade(int? grade) {
    final int value = (grade ?? 10).clamp(1, 17).toInt();

    if (value <= 3) {
      const List<Color> accents = <Color>[
        Color(0xFFF4A261),
        Color(0xFFE9A23B),
        Color(0xFF2A9D8F),
      ];
      return GradeUiProfile(
        stage: GradeStage.lowerPrimary,
        gradeLabel: '小学${_number(value)}年级',
        modeLabel: '兴趣启蒙',
        primary: const Color(0xFF168AAD),
        secondary: accents[value - 1],
        surfaceTint: const Color(0xFFEAF9FC),
        icon: Icons.auto_stories_rounded,
        backgroundAlignment: Alignment.topLeft,
        cardRadius: 18,
        cameraDiameter: 158,
        cameraHeight: 190,
        formula: '3 × 4 = 12',
        formulaAlignment: const Alignment(0.72, -0.58),
      );
    }
    if (value <= 6) {
      const List<Color> primaries = <Color>[
        Color(0xFF2979C9),
        Color(0xFF3F65B5),
        Color(0xFF3F51B5),
      ];
      return GradeUiProfile(
        stage: GradeStage.upperPrimary,
        gradeLabel: '小学${_number(value)}年级',
        modeLabel: '成长进阶',
        primary: primaries[value - 4],
        secondary: const Color(0xFF00A896),
        surfaceTint: const Color(0xFFEDF4FC),
        icon: Icons.explore_rounded,
        backgroundAlignment: Alignment.centerLeft,
        cardRadius: 16,
        cameraDiameter: 150,
        cameraHeight: 180,
        formula: 'S = a × b',
        formulaAlignment: const Alignment(-0.72, -0.48),
      );
    }
    if (value <= 9) {
      const List<Color> primaries = <Color>[
        Color(0xFF16877B),
        Color(0xFF087F75),
        Color(0xFF00796B),
      ];
      return GradeUiProfile(
        stage: GradeStage.middle,
        gradeLabel: '初中${_number(value - 6)}年级',
        modeLabel: '理性探索',
        primary: primaries[value - 7],
        secondary: const Color(0xFF3367B2),
        surfaceTint: const Color(0xFFE8F4F3),
        icon: Icons.hub_rounded,
        backgroundAlignment: Alignment.centerRight,
        cardRadius: 14,
        cameraDiameter: 142,
        cameraHeight: 170,
        formula: 'y = kx + b',
        formulaAlignment: const Alignment(0.72, -0.34),
      );
    }
    if (value <= 12) {
      const List<Color> primaries = <Color>[
        Color(0xFF4857BC),
        Color(0xFF3F51B5),
        Color(0xFF3949AB),
      ];
      return GradeUiProfile(
        stage: GradeStage.high,
        gradeLabel: '高中${_number(value - 9)}年级',
        modeLabel: '专注学习',
        primary: primaries[value - 10],
        secondary: const Color(0xFF167D9A),
        surfaceTint: const Color(0xFFEBEEFA),
        icon: Icons.psychology_alt_rounded,
        backgroundAlignment: Alignment.bottomCenter,
        cardRadius: 12,
        cameraDiameter: 124,
        cameraHeight: 150,
        formula: 'sin²x + cos²x = 1',
        formulaAlignment: const Alignment(-0.62, -0.30),
      );
    }
    if (value <= 16) {
      return GradeUiProfile(
        stage: GradeStage.university,
        gradeLabel: '大学${_number(value - 12)}年级',
        modeLabel: '专业研习',
        primary: Color.lerp(
          const Color(0xFF3E5C76),
          const Color(0xFF294C60),
          (value - 13) / 3,
        )!,
        secondary: const Color(0xFF00838F),
        surfaceTint: const Color(0xFFE9F0F4),
        icon: Icons.account_balance_rounded,
        backgroundAlignment: Alignment.bottomRight,
        cardRadius: 10,
        cameraDiameter: 116,
        cameraHeight: 142,
        formula: '∫ₐᵇ f(x) dx',
        formulaAlignment: const Alignment(0.68, -0.22),
      );
    }
    return const GradeUiProfile(
      stage: GradeStage.research,
      gradeLabel: '研究生',
      modeLabel: '研究分析',
      primary: Color(0xFF5E548E),
      secondary: Color(0xFF46626F),
      surfaceTint: Color(0xFFF0EDF6),
      icon: Icons.science_rounded,
      backgroundAlignment: Alignment.topRight,
      cardRadius: 8,
      cameraDiameter: 108,
      cameraHeight: 136,
      formula: '∇ · F = 0',
      formulaAlignment: Alignment(-0.68, -0.20),
    );
  }

  static String _number(int value) {
    const List<String> labels = <String>['', '一', '二', '三', '四', '五', '六'];
    return value > 0 && value < labels.length ? labels[value] : '$value';
  }
}

class GradeBackdrop extends StatelessWidget {
  const GradeBackdrop({
    super.key,
    required this.profile,
    this.imageAsset = 'assets/images/background.png',
    this.veilStrength = 1,
    this.darkImageOpacity = 0.72,
  });

  final GradeUiProfile profile;
  final String imageAsset;
  final double veilStrength;
  final double darkImageOpacity;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double strength = veilStrength.clamp(0.0, 1.0).toDouble();
    final Color lowerTint = Color.alphaBlend(
      profile.primary.withValues(alpha: isDark ? 0.10 : 0.08),
      isDark ? scheme.surface : profile.surfaceTint,
    );

    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Opacity(
            opacity: isDark ? darkImageOpacity.clamp(0.0, 1.0).toDouble() : 1,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                profile.secondary.withValues(alpha: isDark ? 0.12 : 0.12),
                BlendMode.softLight,
              ),
              child: Image.asset(
                imageAsset,
                fit: BoxFit.cover,
                alignment: profile.backgroundAlignment,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0, 0.52, 1],
                colors: isDark
                    ? <Color>[
                        scheme.surface.withValues(alpha: 0.76 * strength),
                        scheme.surface.withValues(alpha: 0.82 * strength),
                        lowerTint.withValues(alpha: 0.92 * strength),
                      ]
                    : <Color>[
                        profile.surfaceTint.withValues(alpha: 0.58 * strength),
                        profile.surfaceTint.withValues(alpha: 0.70 * strength),
                        lowerTint.withValues(alpha: 0.88 * strength),
                      ],
              ),
            ),
          ),
          Align(
            alignment: profile.formulaAlignment,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                profile.formula,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: profile.primary.withValues(
                    alpha: isDark ? 0.10 : 0.14,
                  ),
                  fontSize: profile.stage == GradeStage.lowerPrimary ? 22 : 20,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
