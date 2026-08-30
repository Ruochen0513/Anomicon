import { LibraryContentRef } from '../../domain/LibraryContentRef';
import { LibraryCollectionVM } from '../viewmodel/LibraryCollectionVM';

/** Library 页面只接收已投影的 ViewModel 与导航回调。 */
export interface LibraryCollectionViewContract {
  viewModel: LibraryCollectionVM;
  scroller: Scroller;
  onOpenContent: (content: LibraryContentRef) => void;
}
