import { Map as ImmutableMap } from 'immutable';
import { ACTIVITY_LOG_ADD, ACTIVITY_LOG_RESET } from '../actions/activity_log';

const initialState = ImmutableMap({
  logs: [],
});

export default function activity_log(state = initialState, action) {
  switch (action.type) {
  case ACTIVITY_LOG_ADD:
    return state.set('logs', [...state.get('logs'), action.value]);
  case ACTIVITY_LOG_RESET:
    return state.set('logs', []);
  default:
    return state;
  }
}
