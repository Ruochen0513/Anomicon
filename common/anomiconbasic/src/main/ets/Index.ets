/** Narrow public surface for cross-feature contracts. */
export {
  ViewModelLoadState,
  ViewModelLifecycle,
  ViewModelErrorInfo,
  ViewModelSnapshot
} from './mvvm/Index';
export {
  AppTypography,
  CACHE_FRESH_DURATION_MS
} from './foundation/Index';
export {
  AppInfoPort,
  HapticFeedbackPort,
  RuntimeClockPort,
  IdGeneratorPort,
  AppInfoAdapter,
  HapticFeedbackAdapter,
  RuntimeClockAdapter,
  IdGeneratorAdapter,
  ExternalUrlPolicy
} from './platform/Index';
export {
  AtomicTextCacheFileStore,
  ANOMICON_DATABASE_NAME
} from './storage/Index';
export {
  ImagePreviewActions
} from './media/Index';
export {
  objectClassColor,
  PHONE_PAGE_MARGIN,
  HDS_TITLE_BAR_HEIGHT_MINI,
  updateWindowAvoidArea,
  pageContentTop,
  immersiveMaterialSupported,
  createAppTitleBarStyle,
  AppBodyText,
  ReadingBodyText,
  SkeletonBlock
} from './ui/Index';
