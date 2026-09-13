import { createReducer } from '@reduxjs/toolkit';

import {
  setWorkshopActivity,
  setWorkshopInboxUrl,
} from 'mastodon/actions/activity_workshop';

interface State {
  // The Workshop's two editors, kept in the store rather than in component state
  // so that the draft survives navigating to another column and back, and so the
  // Activity Log can fill both in before pushing the route.
  activity: string;
  inboxUrl: string;
}

const initialState: State = {
  activity: '',
  inboxUrl: '',
};

export const activityWorkshopReducer = createReducer(
  initialState,
  (builder) => {
    builder
      .addCase(setWorkshopActivity, (state, action) => {
        state.activity = action.payload;
      })
      .addCase(setWorkshopInboxUrl, (state, action) => {
        state.inboxUrl = action.payload;
      });
  },
);
