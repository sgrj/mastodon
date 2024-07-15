import { Map as ImmutableMap } from 'immutable';
import {
  ACTIVITY_WORKSHOP_ACTIVITY,
  ACTIVITY_WORKSHOP_INBOX_URL,
} from '../actions/activity_workshop';

const initialState = ImmutableMap({
  data: null,
  url: '',
});

export default function activity_workshop(state = initialState, action) {
  switch (action.type) {
  case ACTIVITY_WORKSHOP_ACTIVITY:
    return state.set('activity', action.value);
  case ACTIVITY_WORKSHOP_INBOX_URL:
    return state.set('inbox_url', action.value);
  default:
    return state;
  }
}
