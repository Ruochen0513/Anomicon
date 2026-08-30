import { ExploreCollectionMode } from '../../domain/ExploreContracts';

export enum ExploreHomeEventType {
  RETRY_TOP_RATED = 'retry_top_rated',
  RETRY_RECENT = 'retry_recent',
  RETRY_JOKES = 'retry_jokes',
  REFRESH_RECOMMENDATIONS = 'refresh_recommendations',
  DISMISS_RECOMMENDATION = 'dismiss_recommendation',
  REFRESH_DAY = 'refresh_day'
}

export interface ExploreHomeEvent {
  type: ExploreHomeEventType;
}

export enum ExploreCollectionEventType {
  RETRY = 'retry',
  SET_MODE = 'set_mode',
  REFRESH_DAY = 'refresh_day'
}

export interface ExploreCollectionEvent {
  type: ExploreCollectionEventType;
  mode?: ExploreCollectionMode;
}
