import 'package:flutter/material.dart';

const _logoAsset = 'assets/branding/vesnai_logo.png';
const _iconAsset = 'assets/branding/vesnai_icon.png';

/// VesnAI brand mark from [assets/branding/].
class VesnaiLogo extends StatelessWidget {
  const VesnaiLogo({
    super.key,
    this.height = 120,
    this.full = true,
  });

  /// Height of the logo widget.
  final double height;

  /// When true, show the full wordmark artwork; otherwise the square icon crop.
  final bool full;

  /// Pale green wash behind the head in the brand artwork.
  static const brandBackground = Color(0xFFE2E6CE);

  /// Warm cream at the outer edge of the full logo.
  static const brandCream = Color(0xFFE8E6D5);

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      full ? _logoAsset : _iconAsset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}

/// Circular assistant avatar using the VesnAI icon.
class VesnaiAvatar extends StatelessWidget {
  const VesnaiAvatar({super.key, this.radius = 18});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: VesnaiLogo.brandBackground,
      child: ClipOval(
        child: Image.asset(
          _iconAsset,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
