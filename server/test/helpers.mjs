import { once } from 'node:events';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { startServer } from '../server.mjs';

export const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
export async function fixture(t, options = {}) {
  const server = await startServer({ host: '127.0.0.1', port: 0, ...options });
  t.after(() => server.close());
  return server;
}
export async function connect(server, options = {}) {
  const ws = new WebSocket(`ws://127.0.0.1:${server.port}/ws`, options);
  const client = { ws, messages: [], latest: null, room: null, seq: 0, actionSeq: 0 };
  ws.on('error', () => {});
  ws.on('message', raw => {
    const message = JSON.parse(raw);
    client.messages.push(message);
    if (message.type === 'state') client.latest = message;
    if (message.type === 'room') client.room = message;
  });
  client.send = data => ws.send(JSON.stringify(data));
  client.mark = () => client.messages.length;
  client.wait = async (predicate, { from = 0, timeout = 3500 } = {}) => {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      const found = client.messages.slice(from).find(predicate);
      if (found) return found;
      await pause(10);
    }
    throw new Error(`Message not received: ${JSON.stringify(client.messages.slice(-2))}`);
  };
  await once(ws, 'open');
  const welcome = await client.wait(message => message.type === 'welcome');
  assert.equal(welcome.protocol, 4);
  client.id = welcome.id;
  return client;
}
export async function create(client, name = 'Host') {
  const from = client.mark();
  client.send({ type: 'create', protocol: 4, name });
  return client.wait(message => message.type === 'room' && message.code, { from });
}
export async function join(client, code, name = 'Guest') {
  const from = client.mark();
  client.send({ type: 'join', protocol: 4, name, code });
  return client.wait(message => message.type === 'room' && message.code === code, { from });
}
export async function expectError(client, request, expression) {
  const from = client.mark();
  client.send(request);
  const response = await client.wait(message => message.type === 'error', { from });
  assert.match(response.message, expression);
}
export function input(client, x = 0, z = 0, extra = {}) {
  client.send({ type: 'input', x, z, yaw: 0, block: false, sprint: false, crouch: false, seq: client.seq++, ...extra });
}
export function action(client, type) { client.send({ type, action_seq: ++client.actionSeq }); }
export function player(client, id = client.id) { return client.latest?.players.find(item => item.id === id); }
export async function moveTo(client, x, z) {
  const deadline = Date.now() + 6500;
  while (Date.now() < deadline) {
    const p = player(client);
    if (p) {
      const dx = x - p.x, dz = z - p.z;
      if (Math.hypot(dx, dz) < 0.08) { input(client); await pause(80); return; }
      input(client, dx / 0.55, dz / 0.55);
    }
    await pause(50);
  }
  throw new Error('Player could not move to requested coordinates.');
}
export async function requestBattle(host) {
  await moveTo(host, 0, -4);
  const from = host.mark();
  host.send({ type: 'start' });
  return host.wait(message => message.type === 'room' && message.phase === 'ready_check', { from });
}
export async function startBattle(host, clients) {
  await requestBattle(host);
  const from = host.mark();
  for (const client of clients) client.send({ type: 'ready', ready: true });
  return host.wait(message => message.type === 'state' && message.phase === 'playing', { from });
}
