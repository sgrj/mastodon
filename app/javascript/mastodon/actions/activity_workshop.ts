import { createAction } from '@reduxjs/toolkit';

// Both fields are the raw text of an editor, not parsed values: the Workshop's
// whole point is that a student can type something that is not a valid activity
// and watch what happens. The activity is only `JSON.parse`d at submit time.
export const setWorkshopActivity = createAction<string>(
  'activity_workshop/setActivity',
);

export const setWorkshopInboxUrl = createAction<string>(
  'activity_workshop/setInboxUrl',
);
