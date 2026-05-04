import { z } from 'zod'

export const eventSchema = z.object({
  transcriptionAnonymised: z.string().min(1).max(2000),
  intent: z.string().min(1).max(64),
  slotsAnonymised: z.record(z.string(), z.unknown()).default({}),
  parserPath: z.enum([
    'PersonalisationAlias',
    'PersonalisationMemory',
    'FoundationModels',
    'NLModel',
    'KeywordRegex',
    'Unknown',
  ]),
  outcome: z.enum(['confirmed', 'cancelled', 'timedOut', 'unknown']),
  locale: z.string().regex(/^[a-z]{2}-[A-Z]{2}$/),
  timestamp: z.string().datetime({ offset: true }),
  flags: z.array(z.enum(['likelyMisparse', 'recoverableUnknown', 'broadcast'])).default([]),
})

export const batchSchema = z.object({
  deviceId: z.string().uuid(),
  appVersion: z.string().min(1).max(32),
  modelVersion: z.string().min(1).max(64),
  events: z.array(eventSchema).min(1).max(100),
})

export type Batch = z.infer<typeof batchSchema>
export type BatchEvent = z.infer<typeof eventSchema>
