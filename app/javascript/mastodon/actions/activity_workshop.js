export const ACTIVITY_WORKSHOP_ACTIVITY = 'ACTIVITY_WORKSHOP_ACTIVITY';
export const ACTIVITY_WORKSHOP_INBOX_URL = 'ACTIVITY_WORKSHOP_INBOX_URL';

export const setWorkshopActivity = (value) => ({
  type: ACTIVITY_WORKSHOP_ACTIVITY,
  value,
});

export const setWorkshopInboxUrl = (value) => ({
  type: ACTIVITY_WORKSHOP_INBOX_URL,
  value,
});
