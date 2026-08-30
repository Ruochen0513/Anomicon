import {
  ExploreCollectionMode
} from 'explore';
import {
  LibraryCollectionMode,
  LibraryContentRef
} from 'library';
import {
  ExploreCollectionRouteParams,
  LibraryCollectionRouteParams,
  ScpArticleRouteParams,
  resolveArticleRouteContent
} from './AppRoutes';

/**
 * Product-owned route boundary.
 *
 * Router payloads are untrusted serialized values.  These helpers normalize
 * and validate them before a destination activates a screen ViewModel.  They
 * deliberately return only domain values; no NavPathStack or UI object is
 * allowed to leak into feature code.
 */
export function parseExploreCollectionRoute(
  param: Object | null | undefined
): ExploreCollectionRouteParams | undefined {
  if (param === undefined || param === null || typeof param !== 'object') {
    return undefined;
  }
  const candidate = param as ExploreCollectionRouteParams;
  if (candidate.mode !== ExploreCollectionMode.RECENT &&
    candidate.mode !== ExploreCollectionMode.JOKE) {
    return undefined;
  }
  return { mode: candidate.mode };
}

export function parseLibraryCollectionRoute(
  param: Object | null | undefined
): LibraryCollectionRouteParams | undefined {
  if (param === undefined || param === null || typeof param !== 'object') {
    return undefined;
  }
  const candidate = param as LibraryCollectionRouteParams;
  if (candidate.mode !== LibraryCollectionMode.FAVORITES &&
    candidate.mode !== LibraryCollectionMode.CONTINUE_READING &&
    candidate.mode !== LibraryCollectionMode.RECENT) {
    return undefined;
  }
  return { mode: candidate.mode };
}

export function parseArticleRouteContent(
  param: Object | null | undefined
): LibraryContentRef | undefined {
  if (param === undefined || param === null || typeof param !== 'object') {
    return undefined;
  }
  const candidate = param as ScpArticleRouteParams;
  try {
    return resolveArticleRouteContent(candidate);
  } catch (_error) {
    return undefined;
  }
}
