import { createReducer } from '@reduxjs/toolkit';

import {
  addActivityLog,
  resetActivityLog,
} from 'mastodon/actions/activity_log';
import type { ActivityLogEvent } from 'mastodon/models/activity_log';

interface State {
  logs: ActivityLogEvent[];
}

const initialState: State = {
  logs: [],
};

export const activityLogReducer = createReducer(initialState, (builder) => {
  builder
    .addCase(addActivityLog, (state, action) => {
      state.logs.push(action.payload);
    })
    .addCase(resetActivityLog, (state) => {
      state.logs = [];
    });
});
