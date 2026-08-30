/** 本地自然日驱动的稳定内容轮换策略。 */
export class DailyContentPolicy {
  static dayKey(timestamp: number = Date.now()): string {
    const date = new Date(timestamp);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const monthText = month < 10 ? `0${month}` : `${month}`;
    const dayText = day < 10 ? `0${day}` : `${day}`;
    return `${date.getFullYear()}-${monthText}-${dayText}`;
  }

  /**
   * 同一天、同一内容源始终返回相同顺序；日期变化后重新洗牌。
   * 有界去重与线性补齐兼容任意列表长度，不依赖随机数或网络状态。
   */
  static selectIndexes(total: number, count: number, salt: string, dayKey: string): number[] {
    const target = Math.min(Math.max(0, count), Math.max(0, total));
    if (target === 0) {
      return [];
    }
    const seed = DailyContentPolicy.hash(`${dayKey}:${salt}`);
    const start = seed % total;
    const step = total <= 1 ? 1 : (DailyContentPolicy.hash(`${salt}:${dayKey}:step`) % (total - 1)) + 1;
    const indexes: number[] = [];
    const selected: Set<number> = new Set();
    for (let offset = 0; offset < total && indexes.length < target; offset++) {
      const index = (start + offset * step) % total;
      if (!selected.has(index)) {
        selected.add(index);
        indexes.push(index);
      }
    }
    for (let offset = 0; offset < total && indexes.length < target; offset++) {
      const index = (start + offset) % total;
      if (!selected.has(index)) {
        selected.add(index);
        indexes.push(index);
      }
    }
    return indexes;
  }

  private static hash(value: string): number {
    let result: number = 5381;
    for (let index = 0; index < value.length; index++) {
      result = ((result * 33) ^ value.charCodeAt(index)) >>> 0;
    }
    return result;
  }
}
