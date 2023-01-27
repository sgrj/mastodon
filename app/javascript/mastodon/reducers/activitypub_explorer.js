import { Map as ImmutableMap } from 'immutable';
import { ACTIVITYPUB_EXPLORER_DATA, ACTIVITYPUB_EXPLORER_URL } from '../actions/activitypub_explorer';

const initialState = ImmutableMap({
  data: null,
  url: '',
});

export default function activitypub_explorer(state = initialState, action) {
  switch (action.type) {
  case ACTIVITYPUB_EXPLORER_DATA:
    return state.set('data', action.value);
  case ACTIVITYPUB_EXPLORER_URL:
    return state.set('url', action.value);
  default:
    return state;
  }
}
