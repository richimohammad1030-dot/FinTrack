// Logo & identitas KAIT.
//
// KAIT = Kelola Arus Keuangan · Kelola Aset & Income · Kelola Duit.
// "Kait" juga berarti mengait/menarik — harapan agar rezeki terus datang
// dan terkumpul.

import 'package:flutter/material.dart';

import '../../core/theme.dart';

const kaitTagline = 'Kelola Arus Keuangan';
const kaitNavy = Color(0xFF011B38);

class KaitLogo extends StatelessWidget {
  const KaitLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/kait_icon.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Logo KAIT',
      );
}

/// Logo + nama "KAIT" (dipakai di onboarding & pengaturan).
class KaitWordmark extends StatelessWidget {
  const KaitWordmark({super.key, this.size = 40, this.showTagline = true});
  final double size;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KaitLogo(size: size),
        SizedBox(width: size * 0.3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('KAIT',
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: size * 0.62,
                  fontWeight: FontWeight.w800,
                  letterSpacing: size * 0.08,
                  height: 1,
                  color: context.colors.onSurface,
                )),
            if (showTagline) ...[
              SizedBox(height: size * 0.08),
              Text(kaitTagline, style: context.text.bodySmall?.copyWith(fontSize: size * 0.26)),
            ],
          ],
        ),
      ],
    );
  }
}
