import { describe, expect, it } from '@ohos/hypium';
import { ViewModelLoadState } from 'anomiconbasic';
import {
  CatalogContentUseCase,
  CatalogEntry,
  CatalogRepository,
  CatalogSearchUseCase,
  CatalogSearchViewModel,
  CatalogSnapshot,
  CatalogSnapshotSource,
  DEFAULT_SERIES_ID,
  ScpSeriesDescriptor,
  SearchHistoryRepository,
  SearchHistoryUseCase
} from '../main/ets/Index';

/** In-memory cold catalog used to verify the no-cache application path. */
class ColdCatalogRepository implements CatalogRepository {
  loadCalls: number = 0;

  getCached(_seriesId: string): Promise<CatalogSnapshot | undefined> {
    return Promise.resolve(undefined);
  }

  load(series: ScpSeriesDescriptor): Promise<CatalogSnapshot> {
    this.loadCalls += 1;
    return Promise.resolve(new CatalogSnapshot(
      series.id,
      [new CatalogEntry('SCP-173', '雕像')],
      CatalogSnapshotSource.NETWORK,
      321
    ));
  }

  refresh(series: ScpSeriesDescriptor): Promise<CatalogSnapshot> {
    return this.load(series);
  }

  subscribe(_seriesId: string, _listener: (snapshot: CatalogSnapshot) => void): () => void {
    return (): void => {
    };
  }
}

/** Cold catalog whose first network request fails. */
class FailingColdCatalogRepository implements CatalogRepository {
  getCached(_seriesId: string): Promise<CatalogSnapshot | undefined> {
    return Promise.resolve(undefined);
  }

  load(_series: ScpSeriesDescriptor): Promise<CatalogSnapshot> {
    return Promise.reject(new Error('catalog offline'));
  }

  refresh(series: ScpSeriesDescriptor): Promise<CatalogSnapshot> {
    return this.load(series);
  }

  subscribe(_seriesId: string, _listener: (snapshot: CatalogSnapshot) => void): () => void {
    return (): void => {
    };
  }
}

/** Minimal history adapter that still verifies immutable publication. */
class MemorySearchHistoryRepository implements SearchHistoryRepository {
  private values: string[] = ['SCP-049'];

  list(): string[] {
    return this.values.slice();
  }

  add(query: string): void {
    if (query.length > 0) {
      this.values = [query];
    }
  }

  clear(): void {
    this.values = [];
  }
}

async function drainMicrotasks(rounds: number = 20): Promise<void> {
  for (let index = 0; index < rounds; index++) {
    await Promise.resolve();
  }
}

function createSearchViewModel(repository: CatalogRepository): CatalogSearchViewModel {
  return new CatalogSearchViewModel(
    new CatalogSearchUseCase(
      new CatalogContentUseCase(repository),
      new SearchHistoryUseCase(new MemorySearchHistoryRepository())
    ),
    1
  );
}

export default function catalogSearchSnapshotTest(): void {
  describe('CatalogSearchSnapshotContract', () => {
    it('publishes a revisioned immutable snapshot after a cold load', 0, async () => {
      const repository = new ColdCatalogRepository();
      const viewModel = createSearchViewModel(repository);
      const initialRevision = viewModel.snapshot.revision;

      viewModel.activate();
      await drainMicrotasks();

      const loaded = viewModel.snapshot;
      expect(repository.loadCalls).assertEqual(1);
      expect(loaded.revision > initialRevision).assertTrue();
      expect(loaded.state).assertEqual(ViewModelLoadState.READY);
      expect(loaded.error === undefined).assertTrue();
      expect(loaded.fetchedAt).assertEqual(321);
      expect(loaded.data?.query).assertEqual('');
      expect(loaded.data?.seriesId).assertEqual(DEFAULT_SERIES_ID);
      expect(loaded.data?.entries.length).assertEqual(1);
      expect(loaded.data?.random.length).assertEqual(1);
      expect(loaded.data?.history.length).assertEqual(1);
      expect(loaded.data?.catalogPending).assertFalse();
      expect(loaded.data?.entries === viewModel.visibleEntries).assertFalse();
      expect(loaded.data?.random === viewModel.randomItems).assertFalse();
      expect(loaded.data?.history === viewModel.history).assertFalse();

      const loadedRevision = loaded.revision;
      viewModel.setQuery('173');
      expect(viewModel.snapshot.revision > loadedRevision).assertTrue();
      expect(viewModel.snapshot.data?.query).assertEqual('173');
      expect(viewModel.snapshot.data?.entries.length).assertEqual(1);
      expect(viewModel.snapshot.data?.entries[0].itemId).assertEqual('SCP-173');
      viewModel.dispose();
    });

    it('ends the pending state when a cold load fails', 0, async () => {
      const viewModel = createSearchViewModel(new FailingColdCatalogRepository());

      viewModel.activate();
      await drainMicrotasks();

      const failed = viewModel.snapshot;
      expect(failed.revision > 0).assertTrue();
      expect(failed.state).assertEqual(ViewModelLoadState.ERROR);
      expect(failed.error?.message).assertEqual('catalog offline');
      expect(failed.data?.catalogPending).assertFalse();
      expect(failed.data?.entries.length).assertEqual(0);
      viewModel.dispose();
    });
  });
}
