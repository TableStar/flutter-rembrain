final _tagRegex = RegExp(r'#([a-zA-Z0-9_]{1,32})(?![a-zA-Z0-9_])');

Set<String> parseTags(String content) {
  return _tagRegex
      .allMatches(content)
      .map((e) => e.group(1)!.toLowerCase())
      .toSet();
}
