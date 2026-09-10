/// Formats raw number matching code or notification number to preserve leading zeros
/// and full string format (e.g. "012").
String? formatNumberMatchingCode(dynamic rawCode) {
  if (rawCode == null) return null;
  final str = rawCode.toString().trim();
  if (str.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(str) && str.length < 3) {
    return str.padLeft(3, '0');
  }
  return str;
}
