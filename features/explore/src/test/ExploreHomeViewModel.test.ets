import { describe, expect, it } from '@ohos/hypium';
import { ViewModelLoadState } from 'anomiconbasic';
import {
  ExploreDataOrigin,
  ExploreHomeViewModel,
  ExploreLoadedPayload,
  ExploreListRepository,
  ExploreRecommendation,
  ExploreRecommendationEntry,
  ExploreContentUseCase,
  ExploreStoredSnapshot,
  RecommendationRepository,
  RecommendationUseCase,
  ExploreSource,
  ExplorePayload
} from '../main/ets/Index';

/** Content adapter that resolves every index request from memory. */
class ImmediateExploreRepository implements ExploreListRepository {
  read(_source: ExploreSource): Promise<ExploreStoredSnapshot | undefined> {
    return Promise.resolve(undefined);
  }

  isFresh(_snapshot: ExploreStoredSnapshot, _now?: number): boolean {
    return false;
  }

  load(_source: ExploreSource, _forceNetwork?: boolean): Promise<ExploreLoadedPayload> {
    const payload: ExplorePayload = {
      ok: true,
      error: '',
      entries: [{
        url: '/scp-cn-001',
        title: '内存测试条目',
        score: '+1',
        date: '2026-08-30 12:00'
      }]
    };
    return Promise.resolve(new ExploreLoadedPayload(payload, ExploreDataOrigin.NETWORK, 1));
  }

  put(
    _source: ExploreSource,
    _payload: ExplorePayload,
    _fetchedAt?: number
  ): Promise<void> {
    return Promise.resolve();
  }
}

/** Keeps recommendation requests pending so lifecycle invalidation is observable. */
class PendingRecommendationRepository implements RecommendationRepository {
  calls: number = 0;
  private readonly resolvers: Array<(items: ExploreRecommendation[]) => void> = [];

  loadDaily(_batchIndex: number, _dayKey?: string): Promise<ExploreRecommendation[]> {
    this.calls += 1;
    return new Promise<ExploreRecommendation[]>(
      (resolve: (items: ExploreRecommendation[]) => void): void => {
        this.resolvers.push(resolve);
      }
    );
  }

  resolveNext(items: ExploreRecommendation[] = []): void {
    const resolve = this.resolvers.shift();
    resolve?.(items);
  }
}

async function drainMicrotasks(count: number = 24): Promise<void> {
  for (let index: number = 0; index < count; index++) {
    await Promise.resolve();
  }
}

function oneRecommendation(): ExploreRecommendation[] {
  return [new ExploreRecommendation(
    new ExploreRecommendationEntry('SCP-001', '测试推荐'),
  )];
}

export default function exploreHomeViewModelTest(): void {
  describe('ExploreHomeViewModelLoadingContract', () => {
    it('keeps an empty recommendation resume in initial loading state', 0, async () => {
      const recommendationRepository = new PendingRecommendationRepository();
      const viewModel = new ExploreHomeViewModel(
        new ExploreContentUseCase(new ImmediateExploreRepository()),
        new RecommendationUseCase(recommendationRepository),
        (): string => '2026-08-30'
      );

      // Before activate() publishes its first request, IDLE is still an
      // initialization surface and is consumed by the Deck skeleton.
      expect(viewModel.recommendationStatus).assertEqual(ViewModelLoadState.IDLE);
      expect(viewModel.recommendationLoading).assertFalse();

      const firstActivation = viewModel.activate();
      await drainMicrotasks();
      expect(recommendationRepository.calls).assertEqual(1);
      expect(viewModel.recommendationLoading).assertTrue();
      expect(viewModel.recommendationRefreshing).assertFalse();
      expect(viewModel.recommendationStatus).assertEqual(ViewModelLoadState.LOADING);

      viewModel.deactivate();
      expect(viewModel.recommendationLoading).assertFalse();
      expect(viewModel.recommendationRefreshing).assertFalse();
      // No cards exist, so deactivation must leave a resumable initialization
      // state instead of publishing an empty READY/retry surface.
      expect(viewModel.recommendationStatus).assertEqual(ViewModelLoadState.IDLE);

      const secondActivation = viewModel.activate();
      await drainMicrotasks();
      expect(recommendationRepository.calls).assertEqual(2);
      expect(viewModel.recommendationLoading).assertTrue();
      expect(viewModel.recommendationRefreshing).assertFalse();
      expect(viewModel.recommendationStatus).assertEqual(ViewModelLoadState.LOADING);

      // Resolve the stale request first and the current request second. Epoch
      // and token checks must discard the first result without clearing state.
      recommendationRepository.resolveNext(oneRecommendation());
      recommendationRepository.resolveNext(oneRecommendation());
      await firstActivation;
      await secondActivation;
      expect(viewModel.recommendationLoading).assertFalse();
      expect(viewModel.recommendationStatus).assertEqual(ViewModelLoadState.READY);
      viewModel.dispose();
    });
  });
}

