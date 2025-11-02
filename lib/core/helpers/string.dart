String truncate(String s, {int max = 500}) {
  return s.length <= max ? s : '${s.substring(0, max)}…';
}
