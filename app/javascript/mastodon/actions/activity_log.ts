import { createAction } from '@reduxjs/toolkit';

import type { ActivityLogEvent } from 'mastodon/models/activity_log';

export const resetActivityLog = createAction('activity_log/reset');

export const addActivityLog =
  createAction<ActivityLogEvent>('activity_log/add');
