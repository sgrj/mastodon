import { createAction } from '@reduxjs/toolkit';

import type { ActivityLogActivity } from 'mastodon/models/activity_log';

// Seeds for the Explorer column, written by the Activity Log's two link-outs
// before it pushes the route: a URL to fetch, or an activity it already has. It
// has to work that way round -- the column is code-split, so there is nothing to
// call into until the route mounts it. Once mounted the library owns its own
// history, and a student typing a URL into it never comes back through here.
export const setExplorerUrl = createAction<string>(
  'activitypub_explorer/setUrl',
);

export const setExplorerData = createAction<ActivityLogActivity | undefined>(
  'activitypub_explorer/setData',
);

export const resetExplorer = createAction('activitypub_explorer/reset');
