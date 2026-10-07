import { readFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { join } from 'node:path'

export const name = 'vibewand-view'
export const inject = ['connection']

const route = '/api/vibewand.recording'

export function apply(ctx, config = {}) {
  const root = config.root ?? process.env.VIBEWAND_TASKS ?? join(homedir(), 'Library/Application Support/VibeWand/tasks')
  Reflect.get(ctx, 'connection').fetch.register({
    path: route,
    methods: ['GET'],
    requestBody: 'buffered',
    fetch: async (request) => {
      const task = new URL(request.url).searchParams.get('task') ?? ''
      if (!/^\d{8}-\d{6}-[0-9a-f]{6}$/.test(task)) return new Response('no such recording', { status: 404 })
      try {
        return new Response(await readFile(join(root, task, 'voice.wav')), { headers: { 'content-type': 'audio/wav', 'cache-control': 'private, max-age=3600' } })
      } catch {
        return new Response('no such recording', { status: 404 })
      }
    },
  })
}
