export const ACTIVITYPUB_EXPLORER_DATA ='ACTIVITYPUB_EXPLORER_DATA';
export const ACTIVITYPUB_EXPLORER_URL ='ACTIVITYPUB_EXPLORER_URL';

export const setExplorerData = (value) => ({
  type: ACTIVITYPUB_EXPLORER_DATA,
  value,
});

export const setExplorerUrl = (value) => ({
  type: ACTIVITYPUB_EXPLORER_URL,
  value,
});
