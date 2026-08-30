import { describe, expect, it } from '@ohos/hypium';
import { ViewModelLoadState } from 'anomiconbasic';
import {
  FavoriteRepository,
  ReadingHistoryRepository
} from '../main/ets/domain/LibraryRepositories';
import {
  LibraryContentKind,
  LibraryContentRef,
  LibraryFavorite,
  createLibraryContentRef
} from '../main/ets/domain/LibraryContentRef';
import { ReadingHistoryEntry } from '../main/ets/domain/ReadingHistoryEntry';
import { LibraryCollectionMode } from '../main/ets/domain/LibraryContracts';
import { FavoritesViewModel } from '../main/ets/presentation/viewmodel/FavoritesViewModel';
import { ReadingHistoryViewModel } from '../main/ets/presentation/viewmodel/ReadingHistoryViewModel';
import { LibraryCollectionVM } from '../main/ets/presentation/viewmodel/LibraryCollectionVM';

class EmptyFavorites implements FavoriteRepository {
  list(): Promise<LibraryFavorite[]> {
    return Promise.resolve([]);
  }

  toggle(_content: LibraryContentRef): Promise<boolean> {
    return Promise.resolve(false);
  }

  setFavorite(_content: LibraryContentRef, favorite: boolean): Promise<boolean> {
    return Promise.resolve(favorite);
  }
}

class OneItemHistory implements ReadingHistoryRepository {
  private readonly entry: ReadingHistoryEntry = new ReadingHistoryEntry(
    createLibraryContentRef(LibraryContentKind.SCP, 'SCP-173', '雕像'),
    100,
    200,
    24
  );

  list(): Promise<ReadingHistoryEntry[]> {
    return Promise.resolve([this.entry]);
  }

  recordOpened(content: LibraryContentRef): Promise<ReadingHistoryEntry> {
    return Promise.resolve(new ReadingHistoryEntry(content, 100, 200, 0));
  }

  updateProgress(content: LibraryContentRef, offset: number): Promise<ReadingHistoryEntry> {
    return Promise.resolve(new ReadingHistoryEntry(content, 100, 200, offset));
  }

  updateMetadata(_content: LibraryContentRef): Promise<ReadingHistoryEntry | undefined> {
    return Promise.resolve(this.entry);
  }
}

async function drainMicrotasks(rounds: number = 12): Promise<void> {
  for (let index = 0; index < rounds; index++) {
    await Promise.resolve();
  }
}

export default function libraryCollectionSnapshotTest(): void {
  describe('LibraryCollectionSnapshotContract', () => {
    it('publishes immutable data with a monotonic revision', 0, async () => {
      const viewModel = new LibraryCollectionVM(
        new FavoritesViewModel(new EmptyFavorites()),
        new ReadingHistoryViewModel(new OneItemHistory())
      );
      const initialRevision = viewModel.snapshot.revision;

      viewModel.setRouteMode(LibraryCollectionMode.RECENT);
      viewModel.activate();
      await drainMicrotasks();

      expect(viewModel.snapshot.state).assertEqual(ViewModelLoadState.READY);
      expect(viewModel.snapshot.revision > initialRevision).assertTrue();
      expect(viewModel.snapshot.data?.mode).assertEqual(LibraryCollectionMode.RECENT);
      expect(viewModel.snapshot.data?.items.length).assertEqual(1);
      expect(viewModel.snapshot.data?.items[0].content.key).assertEqual('main:scp-173');
      expect(viewModel.snapshot.data?.items === viewModel.items).assertFalse();
      viewModel.dispose();
    });

    it('publishes invalid route errors through the common snapshot', 0, () => {
      const viewModel = new LibraryCollectionVM(
        new FavoritesViewModel(new EmptyFavorites()),
        new ReadingHistoryViewModel(new OneItemHistory())
      );

      viewModel.setRouteMode(undefined);

      expect(viewModel.snapshot.state).assertEqual(ViewModelLoadState.ERROR);
      expect(viewModel.snapshot.error?.code).assertEqual('invalid_route');
      expect(viewModel.snapshot.data?.routeError?.recoverable).assertFalse();
      viewModel.dispose();
    });
  });
}
