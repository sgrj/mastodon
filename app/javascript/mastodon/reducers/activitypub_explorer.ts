import { createReducer } from '@reduxjs/toolkit';

import {
  resetExplorer,
  setExplorerData,
  setExplorerUrl,
} from 'mastodon/actions/activitypub_explorer';
import type { ActivityLogActivity } from 'mastodon/models/activity_log';

interface State {
  // Seeds for <ActivityPubExplorer>'s `initialUrl` / `initialActivityJson`. They
  // are read once, when the column mounts, and cleared when it unmounts -- the
  // Explorer owns its own fetch history after that, so a student who navigates
  // away and back starts from a clean slate rather than a stale one.
  url: string;
  data: ActivityLogActivity | undefined;
}

const initialState: State = {
  url: '',
  data: undefined,
};

export const activitypubExplorerReducer = createReducer(
  initialState,
  (builder) => {
    builder
      .addCase(setExplorerUrl, (state, action) => {
        state.url = action.payload;
        state.data = undefined;
      })
      .addCase(setExplorerData, (state, action) => {
        state.data = action.payload;
        state.url = '';
      })
      .addCase(resetExplorer, () => initialState);
  },
);
