import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Exact vector icons extracted from Figma frames `159:21` and `50:179`.
abstract final class PlayerIcons {
  static const close =
      '<svg width="30" height="30" viewBox="0 0 30 30" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M3.33301 3.33337L26.6663 26.6667M26.6663 3.33337L3.33301 26.6667" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '</svg>';

  static const audioSubtitles =
      '<svg width="33" height="33" viewBox="0 0 33 33" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M2.75 2.75H26.5833C28.4167 2.75 29.3333 3.66667 29.3333 5.5V22C29.3333 23.8333 28.4167 24.75 26.5833 24.75H11.9167L2.75 31.1667V2.75Z" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '<path d="M8.25 11H23.8333M8.25 17.4167H18.3333M22 17.4167H23.8333" stroke-width="2.75" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '</svg>';

  static const settingsGear =
      '<svg width="36" height="36" viewBox="0 0 36 36" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M18 1L20.22 1.15L21.24 5.93L22.78 6.45L24.25 7.17L28.35 4.51L30.02 5.98L31.49 7.65L28.83 11.75L29.55 13.22L30.07 14.76L34.85 15.78L35 18L34.85 20.22L30.07 21.24L29.55 22.78L28.83 24.25L31.49 28.35L30.02 30.02L28.35 31.49L24.25 28.83L22.78 29.55L21.24 30.07L20.22 34.85L18 35L15.78 34.85L14.76 30.07L13.22 29.55L11.75 28.83L7.65 31.49L5.98 30.02L4.51 28.35L7.17 24.25L6.45 22.78L5.93 21.24L1.15 20.22L1 18L1.15 15.78L5.93 14.76L6.45 13.22L7.17 11.75L4.51 7.65L5.98 5.98L7.65 4.51L11.75 7.17L13.22 6.45L14.76 5.93L15.78 1.15L18 1ZM18 10C15.8783 10 13.8434 10.8429 12.3431 12.3431C10.8429 13.8434 10 15.8783 10 18C10 20.1217 10.8429 22.1566 12.3431 23.6569C13.8434 25.1571 15.8783 26 18 26C20.1217 26 22.1566 25.1571 23.6569 23.6569C25.1571 22.1566 26 20.1217 26 18C26 15.8783 25.1571 13.8434 23.6569 12.3431C22.1566 10.8429 20.1217 10 18 10Z" fill-rule="evenodd" clip-rule="evenodd" fill="white"/>'
      '</svg>';

  static const playTriangle =
      '<svg width="32" height="38" viewBox="0 0 32 38" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M1.77734 4.77783L25.7773 19.0001L1.77734 33.2223V4.77783Z" fill="white" stroke-width="1.77778" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '</svg>';

  static const pauseBars =
      '<svg width="28" height="34" viewBox="0 0 28 34" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<rect x="3" y="3" width="7" height="28" rx="2" fill="white"/>'
      '<rect x="18" y="3" width="7" height="28" rx="2" fill="white"/>'
      '</svg>';

  static const rewind10 =
      '<svg width="45" height="48" viewBox="0 0 45 48" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4 24C4 27.7578 5.11433 31.4313 7.20208 34.5558C9.28982 37.6804 12.2572 40.1156 15.729 41.5537C19.2008 42.9918 23.0211 43.368 26.7067 42.6349C30.3924 41.9018 33.7778 40.0922 36.435 37.435C39.0922 34.7778 40.9018 31.3924 41.6349 27.7067C42.368 24.0211 41.9918 20.2008 40.5537 16.729C39.1156 13.2572 36.6804 10.2898 33.5558 8.20208C30.4313 6.11433 26.7578 5 23 5H5M10 10L5 5L10 0" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '</svg>';

  static const forward10 =
      '<svg width="45" height="48" viewBox="0 0 45 48" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M41 24C41 27.7578 39.8857 31.4313 37.7979 34.5558C35.7102 37.6804 32.7428 40.1156 29.271 41.5537C25.7992 42.9918 21.9789 43.368 18.2933 42.6349C14.6077 41.9018 11.2222 40.0922 8.56498 37.435C5.90778 34.7778 4.09821 31.3924 3.36509 27.7067C2.63197 24.0211 3.00823 20.2008 4.4463 16.729C5.88436 13.2572 8.31964 10.2898 11.4442 8.20208C14.5687 6.11433 18.2422 5 22 5H40M35 10L40 5L35 0" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '</svg>';

  static const modalClose =
      '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4 12L12 4M4 4L12 12" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" stroke="#D4D4D4"/>'
      '</svg>';

  static const activeCheck =
      '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M5 13L9 17L19 7" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" stroke="white"/>'
      '</svg>';
}

class PlayerSvgIcon extends StatelessWidget {
  const PlayerSvgIcon(
    this.svg, {
    super.key,
    required this.size,
    this.color,
  });

  final String svg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        svg,
        width: size,
        height: size,
        colorFilter: color != null
            ? ColorFilter.mode(color!, BlendMode.srcIn)
            : null,
      );
}
