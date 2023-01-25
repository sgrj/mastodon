import { Map as ImmutableMap } from 'immutable';
import { ACTIVITYPUB_EXPLORER_DATA } from '../actions/activitypub_explorer';

const initialState = ImmutableMap({
  data: null,
});

export default function activitypub_explorer(state = initialState, action) {
  switch (action.type) {
  case ACTIVITYPUB_EXPLORER_DATA:
    return state.set('data', action.value);
  default:
    return state;
  }
}
