/** 纯策略函数：协调器的时钟来源由系统提供，这里只处理可重复验证的边界。 */
export function readingActivityHasReachedIdle(
  nowUptime: number,
  lastInteractionUptime: number,
  idleTimeoutMs: number
): boolean {
  return lastInteractionUptime >= 0 &&
    nowUptime >= lastInteractionUptime + Math.max(0, idleTimeoutMs);
}

/** 非连续交互最多累计到 idle deadline；延迟回调不能扩大可信时长。 */
export function readingActivityCreditedEndUptime(
  nowUptime: number,
  lastInteractionUptime: number,
  idleTimeoutMs: number
): number {
  if (lastInteractionUptime < 0) {
    return nowUptime;
  }
  return Math.min(nowUptime, lastInteractionUptime + Math.max(0, idleTimeoutMs));
}

/** idle 会话的归档墙钟固定在交互截止点，而不是延迟执行的 timer 时刻。 */
export function readingActivityIdleEndedAt(
  startedAt: number,
  lastInteractionWallTime: number,
  idleTimeoutMs: number
): number {
  return Math.max(
    Math.max(0, startedAt),
    Math.max(0, lastInteractionWallTime) + Math.max(0, idleTimeoutMs)
  );
}
