import { describe, expect, it } from '@ohos/hypium';
import { ViewModelLoadState } from 'anomiconbasic';
import {
  LibraryContentKind,
  LibraryContentRef,
  LibraryFavorite,
  ReadingHistoryEntry,
  ResearchActivitySnapshot,
  ResearchProgress,
  createLibraryContentRef,
  emptyResearchProgress
} from 'library';
import {
  TerminalFavoritesPort,
  TerminalReadingHistoryPort,
  TerminalResearchProfilePort,
  TerminalViewModel,
  TerminalViewModelListener
} from '../main/ets/Index';

class InMemoryFavorites implements TerminalFavoritesPort {
  items: LibraryFavorite[];
  loading: boolean = false;
  error: string = '';
  initialized: boolean = true;
  private readonly listeners: TerminalViewModelListener[] = [];

  constructor(items: LibraryFavorite[]) {
    this.items = items;
  }

  subscribe(listener: TerminalViewModelListener): () => void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  initialize(): Promise<void> {
    return Promise.resolve();
  }

  reload(): Promise<void> {
    return Promise.resolve();
  }

  emit(): void {
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      listeners[index]();
    }
  }

  subscriberCount(): number {
    return this.listeners.length;
  }
}

class InMemoryReadingHistory implements TerminalReadingHistoryPort {
  items: ReadingHistoryEntry[];
  loading: boolean = false;
  error: string = '';
  initialized: boolean = true;
  readonly metadataWrites: LibraryContentRef[] = [];
  private readonly listeners: TerminalViewModelListener[] = [];

  constructor(items: ReadingHistoryEntry[]) {
    this.items = items;
  }

  subscribe(listener: TerminalViewModelListener): () => void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  initialize(): Promise<void> {
    return Promise.resolve();
  }

  reload(): Promise<void> {
    return Promise.resolve();
  }

  updateMetadata(content: LibraryContentRef): Promise<void> {
    this.metadataWrites.push(content);
    const updated: ReadingHistoryEntry[] = [];
    for (let index = 0; index < this.items.length; index++) {
      const entry = this.items[index];
      updated.push(entry.content.key === content.key ? new ReadingHistoryEntry(
        content,
        entry.openedAt,
        entry.lastReadAt,
        entry.scrollOffset
      ) : entry);
    }
    this.items = updated;
    this.emit();
    return Promise.resolve();
  }

  emit(): void {
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      listeners[index]();
    }
  }

  subscriberCount(): number {
    return this.listeners.length;
  }
}

class InMemoryResearchProfile implements TerminalResearchProfilePort {
  profile: ResearchProgress;
  loading: boolean = false;
  error: string = '';
  initialized: boolean = true;
  private readonly listeners: TerminalViewModelListener[] = [];

  constructor(profile: ResearchProgress) {
    this.profile = profile;
  }

  subscribe(listener: TerminalViewModelListener): () => void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  initialize(): Promise<void> {
    return Promise.resolve();
  }

  reload(): Promise<ResearchActivitySnapshot> {
    return Promise.resolve(new ResearchActivitySnapshot(this.profile, undefined));
  }

  emit(): void {
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      listeners[index]();
    }
  }

  subscriberCount(): number {
    return this.listeners.length;
  }
}

class ControlledTitleResolver {
  readonly requests: string[][] = [];
  private resolvePending: ((titles: Map<string, string>) => void) | undefined = undefined;

  resolve(ids: string[]): Promise<Map<string, string>> {
    this.requests.push(ids.slice());
    return new Promise<Map<string, string>>((resolve: (titles: Map<string, string>) => void): void => {
      this.resolvePending = resolve;
    });
  }

  succeed(id: string, title: string): void {
    const titles = new Map<string, string>();
    titles.set(id, title);
    const resolve = this.resolvePending;
    this.resolvePending = undefined;
    resolve?.(titles);
  }
}

class TerminalFixture {
  readonly placeholderContent: LibraryContentRef = createLibraryContentRef(
    LibraryContentKind.SCP,
    'SCP-173',
    'scp-173'
  );
  readonly recentContent: LibraryContentRef = createLibraryContentRef(
    LibraryContentKind.SCP,
    'SCP-049',
    '疫医'
  );
  readonly favorites: InMemoryFavorites = new InMemoryFavorites([
    new LibraryFavorite(this.recentContent, 300)
  ]);
  readonly history: InMemoryReadingHistory = new InMemoryReadingHistory([
    new ReadingHistoryEntry(this.placeholderContent, 100, 300, 48),
    new ReadingHistoryEntry(this.recentContent, 110, 200, 0)
  ]);
  readonly research: InMemoryResearchProfile = new InMemoryResearchProfile(emptyResearchProgress());
  readonly resolver: ControlledTitleResolver = new ControlledTitleResolver();
  readonly viewModel: TerminalViewModel = new TerminalViewModel(
    this.favorites,
    this.history,
    this.research,
    (ids: string[]): Promise<Map<string, string>> => this.resolver.resolve(ids)
  );
}

async function drainMicrotasks(rounds: number = 16): Promise<void> {
  for (let index = 0; index < rounds; index++) {
    await Promise.resolve();
  }
}

export default function terminalViewModelTest(): void {
  describe('TerminalViewModelLifecycle', () => {
    it('projects the current shared state immediately when activated', 0, async () => {
      const fixture = new TerminalFixture();

      fixture.viewModel.activate();

      expect(fixture.viewModel.state).assertEqual(ViewModelLoadState.LOADING);
      expect(fixture.viewModel.favoriteCount).assertEqual(1);
      expect(fixture.viewModel.favoriteEntries[0].content.key).assertEqual('main:scp-049');
      expect(fixture.viewModel.historyCount).assertEqual(2);
      expect(fixture.viewModel.resumeEntries.length).assertEqual(1);
      expect(fixture.viewModel.resumeEntries[0].content.key).assertEqual('main:scp-173');
      expect(fixture.viewModel.recentEntries.length).assertEqual(1);
      expect(fixture.viewModel.recentEntries[0].content.key).assertEqual('main:scp-049');
      expect(fixture.viewModel.profile === fixture.research.profile).assertTrue();

      await drainMicrotasks();
      expect(fixture.viewModel.state).assertEqual(ViewModelLoadState.READY);
      fixture.viewModel.dispose();
    });

    it('drops title enrichment that resolves after deactivation', 0, async () => {
      const fixture = new TerminalFixture();
      fixture.viewModel.activate();
      await drainMicrotasks();
      expect(fixture.resolver.requests.length).assertEqual(1);
      expect(fixture.resolver.requests[0][0]).assertEqual('scp-173');

      fixture.viewModel.deactivate();
      fixture.resolver.succeed('scp-173', '雕像');
      await drainMicrotasks();

      expect(fixture.history.metadataWrites.length).assertEqual(0);
      expect(fixture.viewModel.resumeEntries[0].content.title).assertEqual('scp-173');
      fixture.viewModel.dispose();
    });

    it('disposes idempotently and ignores later source or title results', 0, async () => {
      const fixture = new TerminalFixture();
      fixture.viewModel.activate();
      await drainMicrotasks();
      expect(fixture.resolver.requests.length).assertEqual(1);

      fixture.viewModel.dispose();
      expect(fixture.favorites.subscriberCount()).assertEqual(0);
      expect(fixture.history.subscriberCount()).assertEqual(0);
      expect(fixture.research.subscriberCount()).assertEqual(0);
      fixture.viewModel.dispose();
      fixture.favorites.emit();
      fixture.history.emit();
      fixture.research.emit();
      fixture.viewModel.refresh();
      fixture.viewModel.activate();
      fixture.resolver.succeed('scp-173', '雕像');
      await drainMicrotasks();

      expect(fixture.history.metadataWrites.length).assertEqual(0);
      expect(fixture.favorites.subscriberCount()).assertEqual(0);
      expect(fixture.history.subscriberCount()).assertEqual(0);
      expect(fixture.research.subscriberCount()).assertEqual(0);
    });
  });
}
