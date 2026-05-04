import { z } from 'zod'

export const labelSchema = z.object({
  action: z.enum(['correct', 'incorrect', 'discard']),
  correctedIntent: z.string().min(1).max(64).optional(),
}).refine(
  (d) => !(d.action === 'incorrect' && !d.correctedIntent),
  { message: 'correctedIntent required when action is incorrect', path: ['correctedIntent'] }
)

export type LabelInput = z.infer<typeof labelSchema>
