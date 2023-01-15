export const ACTIVITY_LOG_RESET ='ACTIVITY_LOG_RESET';
export const ACTIVITY_LOG_ADD = 'ACTIVITY_LOG_ADD';

export const resetActivityLog = () => ({
  type: ACTIVITY_LOG_RESET,
});

export const addActivityLog = value => ({
  type: ACTIVITY_LOG_ADD,
  value,
});
