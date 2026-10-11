// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import strconv

struct GameResult {
 title string
 iwad_sha256 string
 demo string
 gametics int
 realtics int
 video_driver string
 replay_matched bool
}

fn doom_timing(result CommandResult) !(int, int) {
 // Upstream Chocolate Doom terminates timedemos through I_Error/exit(-1).
 // Accept only that exact exit and a complete timing record, never a general
 // nonzero result, signal, timeout, output limit or startup error.
 expect(result.exit_code == 255 && !result.timed_out && !result.output_limited,
  'Doom timedemo did not terminate with its expected benchmark exit')!
 for line in result.stderr.split_into_lines() {
  if !line.starts_with('timed ') { continue }
  fields := line.split(' ').filter(it != '')
  expect(fields.len == 8 && fields[2] == 'gametics' && fields[3] == 'in'
   && fields[5] == 'realtics' && fields[6].starts_with('(') && fields[7] == 'fps)',
   'invalid Doom timedemo record')!
  ticks := strconv.atoi(fields[1])!
  real := strconv.atoi(fields[4])!
  expect(ticks > 100 && real > 0, 'Doom timedemo did not execute gameplay')!
  return ticks, real
 }
 return error('Doom did not finish its timedemo')
}

fn (mut suite Suite) doom_timedemo() ! {
 iwad := '/usr/share/games/doom/doom1.wad'
 if !os.is_file(iwad) {
  return error('unsupported: supply a locally licensed DOOM IWAD; game assets are not substituted')
 }
 if suite.path.starts_with('translated-') {
  return error('unsupported: stage a matching foreign Chocolate Doom runtime before game qualification')
 }
 suite.environment['SDL_VIDEODRIVER'] = 'dummy'
 suite.environment['SDL_RENDER_DRIVER'] = 'software'
 suite.environment['SDL_AUDIODRIVER'] = 'dummy'
 suite.environment['XDG_CONFIG_HOME'] = suite.work + '/game-config'
 os.mkdir_all(suite.work + '/game-config')!
 suite.execute('chocolate-doom', ['--version'])!
 bytes := os.read_bytes(iwad)!
 hash := sha256.sum(bytes).hex()
 mut previous := 0
 for iteration in 0 .. 2 {
  count := suite.commands.len
  suite.execute('chocolate-doom', ['-iwad', iwad, '-timedemo', 'demo1', '-nosound',
   '-window', '-width', '320', '-height', '200', '-nograb']) or {
   if suite.commands.len != count + 1 { return err }
   ''
  }
  expect(suite.commands.len == count + 1, 'missing game command receipt')!
  result := suite.commands.last()
  ticks, real := doom_timing(result)!
  expect(iteration == 0 || ticks == previous, 'replayed demo changed gameplay tick count')!
  suite.games << GameResult{'DOOM / Chocolate Doom', hash, 'demo1', ticks, real,
   'SDL dummy / software rendering', iteration == 1}
  previous = ticks
 }
}
