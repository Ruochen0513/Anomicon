import {
  ResearchActivityCheckpoint,
  ResearchActivityFinish,
  ResearchActivitySegment,
  ResearchActivityStart,
  ResearchProgress
} from './ResearchProgress';

/** 一次完整账本读取后发布给展示层的最小快照。 */
export class ResearchActivitySnapshot {
  readonly profile: ResearchProgress;
  readonly activeSession: ResearchActivitySegment | undefined;

  constructor(
    profile: ResearchProgress,
    activeSession: ResearchActivitySegment | undefined
  ) {
    this.profile = profile;
    this.activeSession = activeSession;
  }
}

/** 每个账本写操作都返回已落盘会话及最新画像。 */
export class ResearchActivityMutationResult {
  readonly session: ResearchActivitySegment;
  readonly profile: ResearchProgress;
  readonly activeSession: ResearchActivitySegment | undefined;

  constructor(session: ResearchActivitySegment, snapshot: ResearchActivitySnapshot) {
    this.session = session;
    this.profile = snapshot.profile;
    this.activeSession = snapshot.activeSession;
  }
}

export interface ResearchActivityRepo {
  snapshot(): Promise<ResearchActivitySnapshot>;
  startSession(start: ResearchActivityStart): Promise<ResearchActivityMutationResult>;
  checkpointSession(
    checkpoint: ResearchActivityCheckpoint
  ): Promise<ResearchActivityMutationResult>;
  finalizeSession(finish: ResearchActivityFinish): Promise<ResearchActivityMutationResult>;
}

/**
 * Application-facing sink used by ReadingActivityCoord.
 *
 * Keeping this capability in domain prevents the time/lifecycle coordinator
 * from importing the presentation VM.  The existing ResearchProfileViewModel
 * implements the shape structurally, while tests and future persistence
 * adapters can provide a smaller fake without ArkUI dependencies.
 */
export interface ResearchActivitySink {
  initialize(): Promise<void>;
  startSession(start: ResearchActivityStart): Promise<ResearchActivityMutationResult>;
  checkpointSession(
    checkpoint: ResearchActivityCheckpoint
  ): Promise<ResearchActivityMutationResult>;
  finalizeSession(finish: ResearchActivityFinish): Promise<ResearchActivityMutationResult>;
}
