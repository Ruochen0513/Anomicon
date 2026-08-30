/** Public terminal feature surface; persistence remains in the library HAR. */
export { TerminalHome } from './presentation/view/TerminalHome';
export {
  TerminalViewModel,
  TerminalTitleResolver,
  TerminalViewModelListener,
  TerminalFavoritesPort,
  TerminalReadingHistoryPort,
  TerminalResearchProfilePort
} from './presentation/viewmodel/TerminalViewModel';
export {
  TerminalErrorState,
  TerminalLibrarySectionTitle,
  TerminalReadingHistoryList
} from './presentation/view/TerminalLibraryComponents';
export { TerminalViewContract } from './presentation/view/TerminalViewContracts';
export {
  FOUNDATION_KNOWLEDGE_SECTIONS,
  FoundationKnowledgeIcon,
  FoundationKnowledgeItem,
  FoundationKnowledgeSection,
  FoundationKnowledgeSectionId
} from './presentation/model/FoundationKnowledge';
