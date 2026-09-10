import test from 'node:test';
import assert from 'node:assert/strict';
import {fixture, connect, create, join, input} from './helpers.mjs';

test('server-measured ping updates for all players; unexpected disconnect removes scoreboard member', async t => {
  const server = await fixture(t, {heartbeatMs: 700});
  const host = await connect(server);
  const room = await create(host);
  const guest = await connect(server, {autoPong: false});
  let delay = 120;
  guest.ws.on('ping', data => setTimeout(() => {
    if (guest.ws.readyState === 1) guest.ws.pong(data);
  }, delay));
  await join(guest, room.code);
  const slow = await host.wait(m => m.type === 'state' && m.players.some(p => p.id === guest.id && p.ping_ms >= 100));
  assert.equal(slow.players.length, 2);
  assert.ok(slow.players.find(p => p.id === host.id).ping_ms >= 0);
  delay = 5;
  const from = host.mark();
  input(guest, 0, 0, {ping_ms: 99999});
  const fast = await host.wait(m => m.type === 'state' && m.players.some(p => p.id === guest.id && p.ping_ms !== null && p.ping_ms < 100), {from});
  assert.ok(fast.players.find(p => p.id === guest.id).ping_ms < 100);
  const beforeLeave = host.mark();
  guest.ws.terminate();
  const remaining = await host.wait(m => m.type === 'state' && m.players.length === 1, {from: beforeLeave});
  assert.equal(remaining.players[0].id, host.id);
  host.ws.close();
});
