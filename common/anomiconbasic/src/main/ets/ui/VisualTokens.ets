/** Shared object-class semantic colors. */
export function objectClassColor(objectClass: string): ResourceColor {
  const lower = objectClass.toLowerCase();
  if (lower.includes('keter')) {
    return '#E25C5C';
  }
  if (lower.includes('euclid')) {
    return '#E8A33D';
  }
  if (lower.includes('safe')) {
    return '#5CBB7B';
  }
  if (lower.includes('thaumiel')) {
    return '#7B9FE8';
  }
  return $r('sys.color.font_secondary');
}
