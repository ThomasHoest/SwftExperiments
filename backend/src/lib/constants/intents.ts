export const CANONICAL_INTENTS = [
  'playFavorite', 'playDefault', 'listFavorites',
  'stop', 'pause', 'resume',
  'setVolume', 'adjustVolume', 'mute', 'unmute',
  'joinSpeaker', 'leaveSpeaker',
  'confirm', 'cancel', 'unknown',
] as const

export type CanonicalIntent = typeof CANONICAL_INTENTS[number]
