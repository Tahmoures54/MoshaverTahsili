import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// لوگوی رسمی مکانیک هوشمند
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.size = 96,
    this.showGlow = false,
  });

  final double size;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      BrandAssets.logo,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      semanticLabel: Brand.nameFa,
      errorBuilder: (_, __, ___) => Icon(
        Icons.lock_rounded,
        size: size * 0.45,
        color: Theme.of(context).colorScheme.secondary,
      ),
    );

    if (!showGlow) return image;

    final glow = Theme.of(context).colorScheme.secondary.withOpacity(0.28);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glow,
            blurRadius: size * 0.22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: image,
    );
  }
}

/// عنوان برند برای AppBar: لوگو + نام فارسی
class BrandAppBarTitle extends StatelessWidget {
  const BrandAppBarTitle({super.key, this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandLogo(size: 32),
        const SizedBox(width: 10),
        Flexible(
          child: subtitle == null
              ? const Text(
                  Brand.nameFa,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      Brand.nameFa,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
