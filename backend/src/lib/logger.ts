function emit(level: 'INFO' | 'WARN' | 'ERROR', msg: string, fields?: Record<string, unknown>) {
  const line = JSON.stringify({ ts: new Date().toISOString(), level, msg, ...fields })
  if (level === 'ERROR') console.error(line)
  else if (level === 'WARN') console.warn(line)
  else console.log(line)
}

export const logInfo  = (msg: string, fields?: Record<string, unknown>) => emit('INFO',  msg, fields)
export const logWarn  = (msg: string, fields?: Record<string, unknown>) => emit('WARN',  msg, fields)
export const logError = (msg: string, fields?: Record<string, unknown>) => emit('ERROR', msg, fields)
